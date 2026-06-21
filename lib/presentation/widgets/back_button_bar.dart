import 'package:flutter/material.dart';
import '../../core/design/noir_tokens.dart';

/// 统一的返回按钮 + 返回首页按钮，确保所有二级页面可后退
class BackButtonBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final List<Widget>? actions;
  final Widget? bottom;

  const BackButtonBar({super.key, this.title, this.actions, this.bottom});

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom != null ? kToolbarHeight * 0.6 : 0),
      );

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title != null ? Text(title!, style: const TextStyle(color: NoirTokens.paper)) : null,
      backgroundColor: NoirTokens.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: const IconThemeData(color: NoirTokens.paper),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: NoirTokens.paper),
        tooltip: '返回',
        onPressed: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        },
      ),
      actions: [
        ...?actions,
        if (title != null)
          IconButton(
            icon: const Icon(Icons.home, color: NoirTokens.paper),
            tooltip: '返回首页',
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
      ],
      bottom: bottom != null
          ? PreferredSize(
              preferredSize: const Size.fromHeight(kToolbarHeight * 0.6),
              child: bottom!,
            )
          : null,
    );
  }
}
