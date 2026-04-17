import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// 可复用的 Markdown 气泡组件
///
/// 用于所有 AI 助手/智能体的回复展示，支持：
/// - Markdown 格式化渲染（标题、加粗、列表、代码块、表格等）
/// - 底部标注 AI 模型名称及版本
/// - 暗色/亮色主题自适应
/// - 内容可选中复制
class MarkdownBubble extends StatelessWidget {
  /// AI 回复的 Markdown 内容
  final String content;

  /// 服务商名称（如 "DeepSeek"、"OpenAI"）
  final String? provider;

  /// 模型名称（如 "deepseek-chat"、"gpt-4o"）
  final String? model;

  /// 文本颜色（覆盖主题默认值）
  final Color? textColor;

  /// 是否紧凑模式（聊天气泡内使用更小的字体）
  final bool compact;

  /// 强调色（用于代码高亮、引用条等）
  final Color accentColor;

  const MarkdownBubble({
    super.key,
    required this.content,
    this.provider,
    this.model,
    this.textColor,
    this.compact = false,
    this.accentColor = const Color(0xFF667eea),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseTextColor =
        textColor ?? (isDark ? Colors.white : Colors.black87);
    final baseFontSize = compact ? 13.5 : 14.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Markdown 内容 ──────────────────────────────────────────────
        MarkdownBody(
          data: content,
          selectable: true,
          styleSheet: _buildStyleSheet(
            baseTextColor: baseTextColor,
            baseFontSize: baseFontSize,
            isDark: isDark,
          ),
          onTapLink: (text, href, title) {
            if (href != null) {
              Clipboard.setData(ClipboardData(text: href));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已复制链接: $href'),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          },
        ),

        // ── 模型标签 ────────────────────────────────────────────────────
        if (provider != null && provider!.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildModelLabel(isDark),
        ],
      ],
    );
  }

  /// 模型标注标签
  Widget _buildModelLabel(bool isDark) {
    final labelParts = <String>[];
    if (provider != null && provider!.isNotEmpty) {
      labelParts.add(provider!);
    }
    if (model != null && model!.isNotEmpty) {
      labelParts.add(model!);
    }
    if (labelParts.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.auto_awesome,
          size: 11,
          color: isDark ? Colors.grey[500] : Colors.grey[400],
        ),
        const SizedBox(width: 3),
        Text(
          '由 ${labelParts.join(" · ")} 生成',
          style: TextStyle(
            fontSize: 10.5,
            color: isDark ? Colors.grey[500] : Colors.grey[400],
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  /// 构建 Markdown 样式表
  MarkdownStyleSheet _buildStyleSheet({
    required Color baseTextColor,
    required double baseFontSize,
    required bool isDark,
  }) {
    return MarkdownStyleSheet(
      // ── 段落 ──────────────────────────────────────────────────────
      p: TextStyle(
        fontSize: baseFontSize,
        height: 1.7,
        color: baseTextColor,
      ),

      // ── 标题 ──────────────────────────────────────────────────────
      h1: TextStyle(
        fontSize: baseFontSize + 8,
        fontWeight: FontWeight.bold,
        height: 1.5,
        color: baseTextColor,
      ),
      h2: TextStyle(
        fontSize: baseFontSize + 4,
        fontWeight: FontWeight.bold,
        height: 1.5,
        color: baseTextColor,
      ),
      h3: TextStyle(
        fontSize: baseFontSize + 2,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: baseTextColor,
      ),
      h4: TextStyle(
        fontSize: baseFontSize + 1,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: baseTextColor,
      ),

      // ── 行内样式 ──────────────────────────────────────────────────
      strong: TextStyle(
        fontWeight: FontWeight.bold,
        color: baseTextColor,
      ),
      em: TextStyle(
        fontStyle: FontStyle.italic,
        color: baseTextColor,
      ),
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: baseFontSize - 1,
        color: isDark ? Colors.amber[300] : Colors.deepPurple[700],
        backgroundColor: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.deepPurple.withValues(alpha: 0.06),
      ),

      // ── 代码块 ──────────────────────────────────────────────────
      codeblockPadding: const EdgeInsets.all(14),
      codeblockDecoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),

      // ── 引用块 ──────────────────────────────────────────────────
      blockquoteDecoration: BoxDecoration(
        color: isDark
            ? accentColor.withValues(alpha: 0.08)
            : accentColor.withValues(alpha: 0.04),
        border: Border(
          left: BorderSide(color: accentColor, width: 4),
        ),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),

      // ── 列表 ──────────────────────────────────────────────────────
      listBullet: TextStyle(
        fontSize: baseFontSize,
        color: accentColor,
      ),

      // ── 表格 ──────────────────────────────────────────────────────
      tableHead: TextStyle(
        fontSize: baseFontSize - 1,
        fontWeight: FontWeight.bold,
        color: baseTextColor,
      ),
      tableBody: TextStyle(
        fontSize: baseFontSize - 1,
        color: baseTextColor,
      ),
      tableBorder: TableBorder.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.grey.withValues(alpha: 0.3),
      ),
      tableCellsPadding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),

      // ── 分隔线 ──────────────────────────────────────────────────
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.15)
                : Colors.grey.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),

      // ── 间距 ──────────────────────────────────────────────────────
      blockSpacing: compact ? 8 : 10,
    );
  }
}
