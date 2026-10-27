import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Full-width 48px button used on the login screen.
class AuthButton extends StatefulWidget {
  const AuthButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.backgroundColor,
    required this.textStyle,
    this.leading,
    this.trailing,
    this.shadows = AppShadows.sm,
    this.pressedColor,
  });

  final String label;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final TextStyle textStyle;
  final Widget? leading;
  final Widget? trailing;
  final List<BoxShadow> shadows;
  final Color? pressedColor;

  @override
  State<AuthButton> createState() => _AuthButtonState();
}

class _AuthButtonState extends State<AuthButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);

    return AnimatedScale(
      scale: _pressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 100),
      child: Container(
        height: 48,
        width: double.infinity,
        decoration: BoxDecoration(borderRadius: radius, boxShadow: widget.shadows),
        child: Material(
          color: widget.backgroundColor,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onPressed,
            onHighlightChanged: (value) => setState(() => _pressed = value),
            splashColor: widget.pressedColor,
            highlightColor: widget.pressedColor,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.leading != null) ...[
                    widget.leading!,
                    const SizedBox(width: 12),
                  ],
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: widget.textStyle,
                    ),
                  ),
                  if (widget.trailing != null) ...[
                    const SizedBox(width: 8),
                    widget.trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
