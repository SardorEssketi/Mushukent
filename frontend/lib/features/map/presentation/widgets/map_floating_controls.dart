import 'package:flutter/material.dart';

class MapLayersControl extends StatelessWidget {
  const MapLayersControl({
    super.key,
    required this.label,
    required this.selectedCount,
    required this.totalCount,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final int selectedCount;
  final int totalCount;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final filtered = selectedCount != totalCount;
    return Semantics(
      button: true,
      label: '$label · $selectedCount/$totalCount',
      child: Tooltip(
        message: '$label · $selectedCount/$totalCount',
        child: Material(
          color: filtered ? colors.primaryContainer : colors.surface,
          elevation: 2,
          borderRadius: BorderRadius.circular(15),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              height: 48,
              width: filtered ? 64 : 48,
              child: Column(children: [
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.layers_outlined,
                          size: 23,
                          color: filtered
                              ? colors.onPrimaryContainer
                              : colors.onSurface),
                      if (filtered) ...[
                        const SizedBox(width: 4),
                        Text('$selectedCount',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                    color: colors.onPrimaryContainer,
                                    fontWeight: FontWeight.w800)),
                      ],
                    ],
                  ),
                ),
                if (loading)
                  const SizedBox(height: 2, child: LinearProgressIndicator()),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class MapLocationControl extends StatelessWidget {
  const MapLocationControl({
    super.key,
    required this.label,
    required this.active,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool active;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ink = active ? colors.onPrimaryContainer : colors.onSurface;
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: active ? colors.primaryContainer : colors.surface,
          elevation: 2,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: busy ? null : onPressed,
            child: SizedBox.square(
              dimension: 52,
              child: Center(
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox.square(
                    dimension: 26,
                    child: CustomPaint(
                      painter: _CrosshairPainter(color: ink, active: active),
                    ),
                  ),
                  if (busy)
                    const SizedBox.square(
                      dimension: 37,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  const _CrosshairPainter({required this.color, required this.active});

  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, 6.5, paint);
    canvas.drawLine(const Offset(13, 1), const Offset(13, 4), paint);
    canvas.drawLine(const Offset(13, 22), const Offset(13, 25), paint);
    canvas.drawLine(const Offset(1, 13), const Offset(4, 13), paint);
    canvas.drawLine(const Offset(22, 13), const Offset(25, 13), paint);
    if (active) {
      canvas.drawCircle(center, 2.5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.active != active;
}
