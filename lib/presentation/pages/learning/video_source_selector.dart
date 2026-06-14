import 'package:flutter/material.dart';
import '../../../services/video_source/video_source_manager.dart';

class VideoSourceSelector extends StatelessWidget {
  final String? selectedPlatformId;
  final ValueChanged<String?> onPlatformChanged;

  const VideoSourceSelector({
    super.key,
    this.selectedPlatformId,
    required this.onPlatformChanged,
  });

  @override
  Widget build(BuildContext context) {
    final providers = VideoSourceManager.instance.getAllProviders();
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _buildChip(
            context,
            label: '全部',
            icon: Icons.all_inclusive,
            selected: selectedPlatformId == null,
            themeColor: colorScheme.primary.value,
            onTap: () => onPlatformChanged(null),
          ),
          const SizedBox(width: 8),
          ...providers.map((p) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _buildChip(
                  context,
                  label: p.displayName,
                  icon: p.icon is IconData ? p.icon as IconData : Icons.videocam,
                  selected: selectedPlatformId == p.platformId,
                  themeColor: p.themeColor,
                  enabled: p.enabled,
                  onTap: p.enabled
                      ? () => onPlatformChanged(p.platformId)
                      : null,
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildChip(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool selected,
    required int themeColor,
    bool enabled = true,
    VoidCallback? onTap,
  }) {
    final color = Color(themeColor);

    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: FilterChip(
        avatar: Icon(icon, size: 16, color: selected ? Colors.white : color),
        label: Text(label),
        selected: selected,
        onSelected: onTap != null ? (_) => onTap() : null,
        selectedColor: color,
        checkmarkColor: Colors.white,
        labelStyle: TextStyle(
          color: selected ? Colors.white : null,
          fontSize: 13,
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
