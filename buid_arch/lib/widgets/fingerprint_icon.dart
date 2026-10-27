import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

const _paths = <String>[
  'M12 11c0 2.5-1.5 4.5-3.5 4.5',
  'M12 7c-2.8 0-5 2.2-5 5 0 2.4 1.2 4.6 3 5.8',
  'M15.5 12c0-2-1.5-3.5-3.5-3.5',
  'M12 3.5c-4.7 0-8.5 3.8-8.5 8.5 0 3.2 1.8 6.1 4.5 7.5',
  'M16 8.5c1.2 1 2 2.6 2 4.3 0 2.8-1.5 5.2-3.8 6.5',
  'M8.5 3.8A10 10 0 0 1 12 3c5.5 0 10 4.5 10 10 0 3.2-1.5 6-3.8 7.8',
  'M12 15c0 1-.5 2-1.5 2',
];

/// Line-style fingerprint icon from the design.
/// [compact] uses the simpler 5-line version shown inside buttons.
class FingerprintIcon extends StatelessWidget {
  const FingerprintIcon({
    super.key,
    required this.color,
    this.size = 24,
    this.strokeWidth = 1.6,
    this.compact = false,
  });

  final Color color;
  final double size;
  final double strokeWidth;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final used = compact ? _paths.take(5) : _paths;
    final body = used.map((d) => '<path d="$d"/>').join();
    final svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
        'fill="none" stroke="#000000" stroke-width="$strokeWidth" '
        'stroke-linecap="round" stroke-linejoin="round">$body</svg>';

    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
