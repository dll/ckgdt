import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/design/noir_tokens.dart';
import '../../../core/design/noir_components.dart';
import '../../widgets/noir_page_shell.dart';
import '../../../core/error_handler.dart';

const _projectRoot = r'D:\development\TingChengGIS';

const _subsystems = [
  _Subsystem('g1-textgis', '文本 GIS', '文本分析与地理信息系统结合', Icons.text_fields),
  _Subsystem('g2-audiogis', '音频 GIS', '音频采集与地理信息处理', Icons.headphones),
  _Subsystem('g3-videogis', '视频 GIS', '视频数据与空间信息融合', Icons.videocam),
  _Subsystem('g4-virtualgis', '虚拟 GIS', '虚拟现实与 GIS 交互', Icons.view_in_ar),
  _Subsystem('g5-mixedgis', '混合 GIS', '多模态数据混合处理', Icons.blend),
  _Subsystem('g6-aigis', 'AI GIS', 'AI 驱动的智能地理信息系统', Icons.psychology),
  _Subsystem('g7-opsgis', '运维 GIS', '系统运维与基础设施监控', Icons.dns),
  _Subsystem('g8-portalgis', '门户 GIS', '统一门户与数据可视化', Icons.dashboard),
];

class _Subsystem {
  final String dirName;
  final String name;
  final String description;
  final IconData icon;
  const _Subsystem(this.dirName, this.name, this.description, this.icon);
}

class CasesPage extends StatelessWidget {
  const CasesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return NoirPageShell(
      title: '教学案例',
      eyebrow: 'TEACHING CASES',
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProjectHeader(context),
          const SizedBox(height: 26),
          NoirSectionTitle(
            eyebrow: 'SUBSYSTEMS',
            title: '子系统列表',
            subtitle: '${_subsystems.length} 个子系统 · 均实现三大国产 AI 模型',
            margin: EdgeInsets.zero,
          ),
          const SizedBox(height: NoirTokens.spaceMd),
          ..._subsystems.map((s) => _buildSubsystemCard(context, s)),
        ],
      ),
    );
  }

  Widget _buildProjectHeader(BuildContext context) {
    final dir = Directory(_projectRoot);
    final exists = dir.existsSync();
    return NoirCard(
      padding: const EdgeInsets.all(NoirTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.folder_open, color: NoirTokens.accent, size: 20),
              const SizedBox(width: 10),
              Text('TingChengGIS', style: NoirTokens.title(color: NoirTokens.accent)),
            ],
          ),
          const SizedBox(height: 12),
          Container(width: 36, height: 2, color: NoirTokens.accent),
          const SizedBox(height: 12),
          Text(
            _projectRoot,
            style: NoirTokens.body(color: NoirTokens.ink.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                exists ? Icons.check_circle : Icons.warning,
                size: 14,
                color: exists ? NoirTokens.success : NoirTokens.danger,
              ),
              const SizedBox(width: 6),
              Text(
                exists ? '项目目录存在' : '项目目录不可用',
                style: NoirTokens.muted(size: 11),
              ),
              const Spacer(),
              NoirButton(
                label: '打开文件夹',
                icon: Icons.open_in_new,
                onPressed: exists
                    ? () => _openInExplorer(_projectRoot, context)
                    : null,
                variant: NoirButtonVariant.accent,
                height: 36,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubsystemCard(BuildContext context, _Subsystem sub) {
    final dir = Directory('$_projectRoot\\${sub.dirName}');
    final exists = dir.existsSync();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: NoirCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        onTap: exists ? () => _openInExplorer('$_projectRoot\\${sub.dirName}', context) : null,
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: NoirTokens.inkAlpha(0.06),
                borderRadius: BorderRadius.circular(NoirTokens.radius),
              ),
              child: Icon(sub.icon, size: 20, color: NoirTokens.ink),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sub.name, style: NoirTokens.title()),
                  const SizedBox(height: 2),
                  Text(
                    sub.description,
                    style: NoirTokens.muted(),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub.dirName,
                    style: TextStyle(
                      fontSize: 10,
                      color: NoirTokens.ink.withValues(alpha: 0.35),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            if (exists)
              Icon(Icons.chevron_right, color: NoirTokens.ink.withValues(alpha: 0.25))
            else
              Icon(Icons.folder_off, size: 16, color: NoirTokens.danger),
          ],
        ),
      ),
    );
  }

  void _openInExplorer(String path, BuildContext context) {
    try {
      Process.run('explorer', [path]);
    } catch (e, st) {
      swallowDebug(e, tag: 'CasesPage.openExplorer', stack: st);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开文件夹: $e')),
        );
      }
    }
  }
}
