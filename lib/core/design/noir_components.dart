import 'package:flutter/material.dart';
import 'noir_tokens.dart';

/// Noir 设计系统 — 公共 Widget 组件
///
/// 所有视觉语言收敛到这里：卡片用 [NoirCard]，按钮用 [NoirButton]，
/// 输入框用 [NoirField]，章节标题用 [NoirSectionTitle]，AppBar 用 [NoirAppBar]。

// ─────────────────────────────────────────────────────────────────────────────
// 卡片：1px hairline + 极小圆角 + 可选纸感投影
// ─────────────────────────────────────────────────────────────────────────────

class NoirCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? background;
  final bool elevated;
  final VoidCallback? onTap;

  const NoirCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(NoirTokens.spaceLg),
    this.margin,
    this.background,
    this.elevated = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = background ?? NoirTokens.paper;
    final card = Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(NoirTokens.radius),
        border: Border.all(color: NoirTokens.hairline),
        boxShadow: elevated ? NoirTokens.smallShadow : null,
      ),
      padding: padding,
      child: child,
    );

    final wrapped = onTap == null
        ? card
        : Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(NoirTokens.radius),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(NoirTokens.radius),
              child: card,
            ),
          );

    return margin == null ? wrapped : Padding(padding: margin!, child: wrapped);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 按钮：黑底 + 琥珀方块图标 + 大字距
// ─────────────────────────────────────────────────────────────────────────────

enum NoirButtonVariant { primary, ghost, accent }

class NoirButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final NoirButtonVariant variant;
  final bool loading;
  final bool fullWidth;
  final double height;

  const NoirButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = NoirButtonVariant.primary,
    this.loading = false,
    this.fullWidth = false,
    this.height = 50,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || loading;
    final (bg, fg, border) = switch (variant) {
      NoirButtonVariant.primary => (
          disabled ? NoirTokens.inkAlpha(0.5) : NoirTokens.ink,
          NoirTokens.paper,
          null,
        ),
      NoirButtonVariant.ghost => (
          Colors.transparent,
          NoirTokens.ink,
          NoirTokens.inkAlpha(0.4),
        ),
      NoirButtonVariant.accent => (
          NoirTokens.accent,
          NoirTokens.ink,
          null,
        ),
    };

    final btn = Material(
      color: bg,
      borderRadius: BorderRadius.circular(NoirTokens.radius),
      child: InkWell(
        onTap: disabled ? null : onPressed,
        borderRadius: BorderRadius.circular(NoirTokens.radius),
        child: Container(
          height: height,
          decoration: border == null
              ? null
              : BoxDecoration(
                  border: Border.all(color: border),
                  borderRadius: BorderRadius.circular(NoirTokens.radius),
                ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            mainAxisAlignment: icon == null
                ? MainAxisAlignment.center
                : MainAxisAlignment.spaceBetween,
            mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Text(label, style: NoirTokens.button(color: fg)),
              if (icon != null) ...[
                const SizedBox(width: 14),
                loading
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: variant == NoirButtonVariant.accent
                              ? NoirTokens.ink
                              : NoirTokens.accent,
                        ),
                      )
                    : Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: variant == NoirButtonVariant.primary
                              ? NoirTokens.accent
                              : NoirTokens.ink.withOpacity(0.08),
                          borderRadius:
                              BorderRadius.circular(NoirTokens.radius),
                        ),
                        child: Icon(icon,
                            size: 14,
                            color: variant == NoirButtonVariant.primary
                                ? NoirTokens.ink
                                : fg),
                      ),
              ],
            ],
          ),
        ),
      ),
    );

    return fullWidth ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 输入框：浮动 caps 小标 + 单线下划线 + focus 加粗
// ─────────────────────────────────────────────────────────────────────────────

class NoirField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int? maxLines;

  const NoirField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.suffix,
    this.validator,
    this.keyboardType,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 4),
          child: Text(
            label,
            style: TextStyle(
              color: NoirTokens.inkAlpha(0.55),
              fontSize: NoirTokens.fsSerial,
              letterSpacing: 2.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          validator: validator,
          keyboardType: keyboardType,
          maxLines: obscure ? 1 : maxLines,
          style: const TextStyle(
            color: NoirTokens.ink,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            letterSpacing: NoirTokens.letterBody,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: NoirTokens.inkAlpha(0.3),
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
            suffixIcon: suffix,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
            ),
            border: UnderlineInputBorder(
              borderSide: BorderSide(color: NoirTokens.inkAlpha(0.25)),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: NoirTokens.inkAlpha(0.25)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: NoirTokens.ink, width: 1.5),
            ),
            errorStyle: const TextStyle(fontSize: 11, height: 1.2),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 章节标题
// ─────────────────────────────────────────────────────────────────────────────

class NoirSectionTitle extends StatelessWidget {
  final String? eyebrow;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry margin;

  const NoirSectionTitle({
    super.key,
    this.eyebrow,
    required this.title,
    this.subtitle,
    this.trailing,
    this.margin = const EdgeInsets.symmetric(vertical: NoirTokens.spaceMd),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 38,
            margin: const EdgeInsets.only(right: 14, top: 4),
            color: NoirTokens.ink,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(eyebrow!,
                      style: NoirTokens.caps(color: NoirTokens.accent)),
                  const SizedBox(height: 4),
                ],
                Text(title, style: NoirTokens.section()),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: NoirTokens.muted()),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chip
// ─────────────────────────────────────────────────────────────────────────────

class NoirChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  const NoirChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(NoirTokens.radius),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? NoirTokens.ink : Colors.transparent,
          border: Border.all(
            color: selected ? NoirTokens.ink : NoirTokens.inkAlpha(0.2),
          ),
          borderRadius: BorderRadius.circular(NoirTokens.radius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 14,
                  color: selected ? NoirTokens.accent : NoirTokens.ink),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? NoirTokens.paper : NoirTokens.ink,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppBar
// ─────────────────────────────────────────────────────────────────────────────

class NoirAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? eyebrow;
  final List<Widget>? actions;
  final Widget? leading;
  final bool implyLeading;
  final PreferredSizeWidget? bottom;

  const NoirAppBar({
    super.key,
    required this.title,
    this.eyebrow,
    this.actions,
    this.leading,
    this.implyLeading = true,
    this.bottom,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(58 + (bottom?.preferredSize.height ?? 1));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: NoirTokens.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      automaticallyImplyLeading: implyLeading,
      iconTheme: const IconThemeData(color: NoirTokens.paper),
      leading: leading,
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (eyebrow != null)
            Text(eyebrow!,
                style: NoirTokens.caps(
                    color: NoirTokens.accent, size: 9)),
          Text(
            title,
            style: const TextStyle(
              color: NoirTokens.paper,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
      actions: actions,
      bottom: bottom ??
          PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(
              height: 1,
              color: NoirTokens.accent.withOpacity(0.6),
            ),
          ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat 数字立柱
// ─────────────────────────────────────────────────────────────────────────────

class NoirStatPillar extends StatelessWidget {
  final String serial;
  final String value;
  final String label;
  final Color? valueColor;

  const NoirStatPillar({
    super.key,
    required this.serial,
    required this.value,
    required this.label,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(serial, style: NoirTokens.serial(color: NoirTokens.accent)),
        const SizedBox(height: 6),
        Container(width: 24, height: 1, color: NoirTokens.inkAlpha(0.4)),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? NoirTokens.ink,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
              color: NoirTokens.inkAlpha(0.55),
              fontSize: 11,
              letterSpacing: 1.4,
            )),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hairline 分隔线
// ─────────────────────────────────────────────────────────────────────────────

class NoirHairline extends StatelessWidget {
  final double height;
  final double opacity;
  const NoirHairline({super.key, this.height = 1, this.opacity = 0.10});

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        color: NoirTokens.ink.withOpacity(opacity),
      );
}
