# Plan: CKGDT Resource Package Versioning

## Context

The CKGDT resource package (`data/CKGDT/`) has 151+ files across 12 categories, but **zero programmatic versioning**. The `manifest.json` and `res_index.json` both carry `version` fields that are **never read by any Dart code**. The `resource_files` DB table tracks file paths but has no version, hash, or sync timestamp. `CourseResourceService` always overwrites its SharedPreferences cache without comparing versions. There is no integrity verification anywhere in the loading pipeline.

**Pain points:**
- No way to detect if local resources are stale vs. remote (Gitee `mad-data`)
- No integrity check after download — corrupted files go undetected
- No migration path when resource structure changes between versions
- No admin visibility into "what version of resources am I running?"
- Config files loaded from 3 different sources (assets, Gitee, SharedPreferences) with no unified version

## Goal

Introduce version tracking, integrity verification, and incremental sync for the resource package system, so the platform can:
1. Know what version of each resource is loaded
2. Detect staleness vs. remote (Gitee)
3. Verify integrity after download
4. Provide admin visibility and manual sync control

---

## Step 1: Enhance `manifest.json` Schema

**File:** `data/CKGDT/配置/manifest.json`

Add per-resource checksums and structured metadata:

```json
{
  "schema_version": "2.0.0",
  "package_version": "1.1.0",
  "course_id": "ckgdt",
  "course_name": "课程知识图谱与数字孪生平台",
  "last_updated": "2026-07-03",
  "min_app_version": "2.1.0",
  "resources": {
    "chapters": {
      "file": "chapters.json",
      "version": "1.0.0",
      "checksum": "sha256:...",
      "remote_path": "course_config/chapters.json"
    },
    "assessment": {
      "file": "assessment.json",
      "version": "2.0.0",
      "checksum": "sha256:...",
      "remote_path": "course_config/assessment.json"
    },
    "lab_tasks": {
      "file": "lab_tasks.json",
      "version": "1.0.0",
      "checksum": "sha256:...",
      "remote_path": "course_config/lab_tasks.json"
    },
    "report_templates": {
      "file": "report_templates.json",
      "version": "1.0.0",
      "checksum": "sha256:...",
      "remote_path": "course_config/report_templates.json"
    },
    "res_index": {
      "file": "res_index.json",
      "version": "2.0.0",
      "checksum": "sha256:...",
      "remote_path": "course_config/res_index.json"
    }
  }
}
```

Also create a Python tool `tools/compute_resource_checksums.py` that:
- Reads all JSON files in `data/CKGDT/配置/`
- Computes SHA-256 of each file's normalized content (sorted keys, no whitespace)
- Outputs updated `manifest.json` with checksums filled in
- Run periodically or when configs change

---

## Step 2: New DB Table `resource_packages`

**File:** `lib/data/local/database_helper.dart`

Add V37 migration to create:

```sql
CREATE TABLE IF NOT EXISTS resource_packages(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  course_id TEXT NOT NULL,
  package_key TEXT NOT NULL,       -- e.g., 'chapters', 'assessment', 'lab_tasks'
  version TEXT NOT NULL,            -- semver from manifest.json
  checksum TEXT,                    -- SHA-256 of file content
  file_path TEXT NOT NULL,          -- local path: 'data/CKGDT/配置/chapters.json'
  remote_path TEXT,                 -- Gitee path: 'course_config/chapters.json'
  last_synced_at TEXT,              -- ISO8601 timestamp
  created_at TEXT DEFAULT (datetime('now')),
  UNIQUE(course_id, package_key)
);
```

Also add columns to `resource_files`:
```sql
ALTER TABLE resource_files ADD COLUMN version TEXT;
ALTER TABLE resource_files ADD COLUMN checksum TEXT;
ALTER TABLE resource_files ADD COLUMN last_modified TEXT;
```

And add to `courses`:
```sql
ALTER TABLE courses ADD COLUMN resource_version TEXT;
ALTER TABLE courses ADD COLUMN resource_synced_at TEXT;
```

---

## Step 3: New Model `ResourcePackageModel`

**File:** `lib/data/models/resource_package_model.dart` (new)

```dart
class ResourcePackageModel {
  final int? id;
  final String courseId;
  final String packageKey;   // 'chapters', 'assessment', etc.
  final String version;
  final String? checksum;
  final String filePath;
  final String? remotePath;
  final DateTime? lastSyncedAt;
  final DateTime? createdAt;
  // fromMap / toMap / copyWith
}
```

---

## Step 4: New DAO `ResourcePackageDao`

**File:** `lib/data/local/resource_package_dao.dart` (new)

Methods:
- `getByCourse(courseId)` → List<ResourcePackageModel>
- `getPackage(courseId, packageKey)` → ResourcePackageModel?
- `upsert(ResourcePackageModel)` → void
- `recordSync(courseId, packageKey, version, checksum)` → void
- `getAllVersions(courseId)` → Map<String, String> (packageKey → version)

---

## Step 5: New Service `ResourceVersionService`

**File:** `lib/services/resource_version_service.dart` (new)

Core responsibilities:
1. **Parse manifest.json** — read `schema_version`, `package_version`, per-resource `version` and `checksum`
2. **Compare versions** — local DB version vs. manifest version; return list of packages needing update
3. **Verify integrity** — compute SHA-256 of local file, compare against manifest checksum
4. **Record sync** — after loading/updating, record version + checksum in `resource_packages` table
5. **Detect staleness** — compare `last_synced_at` against a configurable threshold

Key methods:
```dart
class ResourceVersionService {
  /// Parse manifest.json and return structured data
  Future<ManifestData> parseManifest(String courseId);
  
  /// Compare local DB versions against manifest; return packages needing update
  Future<List<PackageDiff>> checkForUpdates(String courseId);
  
  /// Verify integrity of a single resource file
  Future<bool> verifyIntegrity(String filePath, String expectedChecksum);
  
  /// Record that a package was synced
  Future<void> recordSync(String courseId, String packageKey, String version, String checksum);
  
  /// Get summary for admin UI: {packageKey: {version, checksum, lastSynced, status}}
  Future<Map<String, PackageStatus>> getStatusSummary(String courseId);
}
```

---

## Step 6: Enhance `CourseResourceService` with Version Comparison

**File:** `lib/services/course_resource_service.dart`

Modify `_cachedJsonList()` (or similar fetch methods) to:
1. Read manifest.json from Gitee (or local fallback)
2. Compare remote version against local DB `resource_packages` version
3. **Only overwrite SharedPreferences cache if remote version is newer**
4. Record sync timestamp after successful fetch

Add new method:
```dart
/// Fetch manifest from remote, compare with local, return diff
Future<ManifestDiff> checkRemoteManifest(String courseId);
```

---

## Step 7: Enhance `CourseAssetResolver` with Version Awareness

**File:** `lib/services/course_asset_resolver.dart`

Add optional version-check method:
```dart
/// Load asset and verify integrity against expected checksum
Future<String?> loadAssetVerified(String category, String relativePath, {String? expectedChecksum});
```

This calls existing `loadAsset()`, then computes SHA-256 and compares. Returns null if mismatch (logs warning).

---

## Step 8: Update `DataLoadingService` to Record Versions

**File:** `lib/services/data_loading_service.dart`

After `_prefetchRemoteConfigs()` succeeds, call `ResourceVersionService.recordSync()` for each config that was loaded. This ensures the DB tracks what version was last synced.

---

## Step 9: Admin Resource Version Display

**File:** `lib/presentation/pages/settings/resource_version_page.dart` (new)

A simple page accessible from admin settings that shows:
- Package version (from manifest)
- Per-resource status: version, checksum (truncated), last synced, sync status (up-to-date / stale / missing)
- "Sync Now" button that triggers `CourseResourceService.forceRefresh()` + version recording
- Integrity check button that verifies all local files against manifest checksums

**File:** `lib/presentation/pages/home/settings_page.dart`

Add entry under "管理员设置" section:
```dart
_buildMenuItem(
  context,
  icon: Icons.inventory_2,
  title: '资源版本管理',
  subtitle: '查看课程资源包版本与同步状态',
  onTap: () => Navigator.push(context,
    MaterialPageRoute(builder: (_) => const ResourceVersionPage())),
),
```

---

## Step 10: Checksum Computation Script

**File:** `tools/compute_resource_checksums.py` (new)

Python script that:
1. Reads all `*.json` files in `data/CKGDT/配置/`
2. For each file: normalize (sort keys, compact JSON), compute SHA-256
3. Reads existing `manifest.json`, updates `resources[key].checksum` fields
4. Updates `package_version` if any resource version changed
5. Writes back `manifest.json`

Usage: `python tools/compute_resource_checksums.py`

---

## Files to Modify

| File | Change |
|------|--------|
| `data/CKGDT/配置/manifest.json` | Enhance schema with per-resource checksums, schema_version |
| `lib/data/local/database_helper.dart` | V37 migration: create `resource_packages`, add columns to `resource_files` and `courses` |
| `lib/data/models/resource_package_model.dart` | **New** — model class |
| `lib/data/local/resource_package_dao.dart` | **New** — DAO for resource_packages |
| `lib/services/resource_version_service.dart` | **New** — version comparison, integrity check, sync recording |
| `lib/services/course_resource_service.dart` | Add version comparison before cache overwrite |
| `lib/services/course_asset_resolver.dart` | Add integrity-verified loading |
| `lib/services/data_loading_service.dart` | Record versions after prefetch |
| `lib/presentation/pages/settings/resource_version_page.dart` | **New** — admin UI |
| `lib/presentation/pages/home/settings_page.dart` | Add entry for resource version page |
| `tools/compute_resource_checksums.py` | **New** — checksum computation script |

## Verification

1. Run `flutter analyze lib/` — 0 new errors
2. Run `python tools/compute_resource_checksums.py` — manifest.json updated with checksums
3. Launch app → Settings → 管理员设置 → 资源版本管理: shows all packages with versions and "up-to-date" status
4. Simulate stale: change a config file → re-check → shows "stale" status
5. Run `flutter build windows --release` — builds successfully
