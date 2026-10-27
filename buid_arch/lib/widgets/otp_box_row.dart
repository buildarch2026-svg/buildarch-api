import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Six separate boxes for entering an OTP, with auto-advance and
/// auto-backspace between boxes. Uses the system keyboard.
class OtpBoxRow extends StatefulWidget {
  const OtpBoxRow({
    super.key,
    required this.length,
    required this.onChanged,
    required this.hasError,
  });

  final int length;
  final ValueChanged<String> onChanged;
  final bool hasError;

  @override
  State<OtpBoxRow> createState() => OtpBoxRowState();
}

class OtpBoxRowState extends State<OtpBoxRow> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers =
        List.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  /// Clears every box and returns focus to the first one.
  void clear() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes.first.requestFocus();
    widget.onChanged('');
  }

  void _emit() {
    widget.onChanged(_controllers.map((c) => c.text).join());
  }

  void _onChanged(int index, String value) {
    if (value.isNotEmpty) {
      // Only keep the last typed character (handles paste into one box too).
      final digit = value.characters.last;
      _controllers[index].text = digit;
      _controllers[index].selection =
          TextSelection.collapsed(offset: digit.length);
      if (index < widget.length - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
      }
    }
    _emit();
  }

  void _onBackspace(int index) {
    if (_controllers[index].text.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
      _emit();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(widget.length, (i) {
        return _OtpBox(
          controller: _controllers[i],
          focusNode: _focusNodes[i],
          hasError: widget.hasError,
          onChanged: (v) => _onChanged(i, v),
          onBackspace: () => _onBackspace(i),
        );
      }),
    );
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.hasError,
    required this.onChanged,
    required this.onBackspace,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasError;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError
        ? AppColors.error
        : focusNode.hasFocus
            ? AppColors.primaryContainer
            : AppColors.border;

    return SizedBox(
      width: 48,
      height: 48,
      child: KeyboardListener(
        focusNode: FocusNode(skipTraversal: true),
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              controller.text.isEmpty) {
            onBackspace();
          }
        },
        child: AnimatedBuilder(
          animation: focusNode,
          builder: (context, child) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: borderColor,
                  width: focusNode.hasFocus || hasError ? 1.5 : 1,
                ),
                boxShadow: focusNode.hasFocus && !hasError
                    ? [
                        BoxShadow(
                          color: AppColors.primaryContainer.withAlpha(31),
                          blurRadius: 6,
                          spreadRadius: 2,
                        ),
                      ]
                    : const [],
              ),
              child: child,
            );
          },
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 1,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: AppTextStyles.titleMd.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            decoration: const InputDecoration(
              counterText: '',
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    );
  }
}
