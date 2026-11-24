import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_design_tokens.dart';

/// Opens the circular crop editor for [source] and returns the cropped
/// square as PNG bytes, or null when the user cancels.
Future<Uint8List?> showAvatarCropEditor(
  BuildContext context,
  Uint8List source,
) {
  return Navigator.of(context).push<Uint8List>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => AvatarCropEditor(source: source),
  ));
}

/// Pan, zoom and rotation of the photo under a centred circle of diameter
/// [diameter]. [offset] is where the image centre sits relative to the circle
/// centre, in screen pixels. Pure maths, shared by the preview and the export
/// so the uploaded crop is exactly what the user saw.
@immutable
class AvatarCropView {
  const AvatarCropView({
    required this.imageSize,
    required this.diameter,
    this.zoom = 1,
    this.rotation = 0,
    this.offset = Offset.zero,
  });

  static const double maxZoom = 6;

  final Size imageSize;
  final double diameter;

  /// 1 = the photo's short side just fills the circle.
  final double zoom;

  /// Radians, clockwise.
  final double rotation;
  final Offset offset;

  /// Screen pixels per image pixel.
  double get scale =>
      diameter / math.min(imageSize.width, imageSize.height) * zoom;

  static Offset _rotate(Offset v, double angle) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
  }

  /// The image point (relative to the image centre) shown at [screen], a
  /// point relative to the circle centre.
  Offset imagePointAt(Offset screen) =>
      _rotate(screen - offset, -rotation) / scale;

  AvatarCropView copyWith({
    double? zoom,
    double? rotation,
    Offset? offset,
    double? diameter,
  }) =>
      AvatarCropView(
        imageSize: imageSize,
        diameter: diameter ?? this.diameter,
        zoom: zoom ?? this.zoom,
        rotation: rotation ?? this.rotation,
        offset: offset ?? this.offset,
      );

  /// Keeps the whole circle on the photo: no empty area inside the crop.
  AvatarCropView clamped() {
    final z = zoom.clamp(1.0, maxZoom).toDouble();
    final view = copyWith(zoom: z);
    final radius = diameter / 2 / view.scale;
    final maxX = math.max(0.0, imageSize.width / 2 - radius);
    final maxY = math.max(0.0, imageSize.height / 2 - radius);
    final centre = view.imagePointAt(Offset.zero);
    final kept = Offset(
      centre.dx.clamp(-maxX, maxX).toDouble(),
      centre.dy.clamp(-maxY, maxY).toDouble(),
    );
    return view.copyWith(offset: -_rotate(kept, rotation) * view.scale);
  }

  /// A pinch/drag/rotate step: the image point that was under [startFocal]
  /// stays under [focal]. Focal points are relative to the circle centre.
  AvatarCropView gesture({
    required Offset startFocal,
    required Offset focal,
    required double scaleFactor,
    required double rotationDelta,
  }) {
    final anchor = imagePointAt(startFocal);
    final next = copyWith(
      zoom: (zoom * scaleFactor).clamp(1.0, maxZoom).toDouble(),
      rotation: rotation + rotationDelta,
    );
    return next
        .copyWith(offset: focal - _rotate(anchor, next.rotation) * next.scale)
        .clamped();
  }

  /// Zoom or rotate around the circle centre (slider and rotate button).
  AvatarCropView around({double? zoom, double? rotation}) => gesture(
        startFocal: Offset.zero,
        focal: Offset.zero,
        scaleFactor: (zoom ?? this.zoom) / this.zoom,
        rotationDelta: (rotation ?? this.rotation) - this.rotation,
      );

  /// Draws the photo with the circle centre at the canvas origin.
  void paint(Canvas canvas, ui.Image image) {
    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..rotate(rotation)
      ..scale(scale);
    canvas.drawImage(
      image,
      Offset(-imageSize.width / 2, -imageSize.height / 2),
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
  }

  /// Side of the exported square: the photo pixels under the circle, kept
  /// between 256 and 1024 so the upload is sharp but small.
  int get outputSide => (diameter / scale).round().clamp(256, 1024);
}

/// Renders the circle's bounding square of [view] to PNG bytes.
Future<Uint8List> renderAvatarCrop(AvatarCropView view, ui.Image image) async {
  final side = view.outputSide;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final factor = side / view.diameter;
  canvas
    ..scale(factor)
    ..translate(view.diameter / 2, view.diameter / 2);
  view.paint(canvas, image);
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(side, side);
  picture.dispose();
  try {
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Could not encode the cropped photo.');
    return data.buffer.asUint8List();
  } finally {
    rendered.dispose();
  }
}

class AvatarCropEditor extends ConsumerStatefulWidget {
  const AvatarCropEditor({super.key, required this.source});

  final Uint8List source;

  @override
  ConsumerState<AvatarCropEditor> createState() => _AvatarCropEditorState();
}

class _AvatarCropEditorState extends ConsumerState<AvatarCropEditor> {
  ui.Image? _image;
  AvatarCropView? _view;
  AvatarCropView? _gestureStart;
  Offset _gestureStartFocal = Offset.zero;
  bool _failed = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_decode());
  }

  Future<void> _decode() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.source);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  AvatarCropView _viewFor(ui.Image image, double diameter) {
    final current = _view;
    if (current == null) {
      return AvatarCropView(
        imageSize: Size(image.width.toDouble(), image.height.toDouble()),
        diameter: diameter,
      );
    }
    if (current.diameter == diameter) return current;
    // Window resized: keep the same framing at the new circle size.
    final ratio = diameter / current.diameter;
    return current
        .copyWith(diameter: diameter, offset: current.offset * ratio)
        .clamped();
  }

  Future<void> _done() async {
    final image = _image;
    final view = _view;
    if (image == null || view == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = await renderAvatarCrop(view, image);
      if (mounted) Navigator.of(context).pop(bytes);
    } catch (_) {
      if (mounted) {
        setState(() {
          _exporting = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final image = _image;
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Theme.of(context).colorScheme.primary,
      ),
      child: Builder(builder: (context) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            automaticallyImplyLeading: false,
            title: Text(strings.profilePhoto),
            leading: IconButton(
              tooltip: strings.cancel,
              onPressed: _exporting ? null : () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ),
          body: SafeArea(
            child: Column(children: [
              Expanded(
                child: _failed
                    ? Center(child: Text(strings.couldNotPreparePhoto))
                    : image == null
                        ? const Center(child: CircularProgressIndicator())
                        : LayoutBuilder(builder: (context, constraints) {
                            final area = constraints.biggest;
                            final diameter = math.max(
                                120.0, area.shortestSide - 2 * AppSpacing.xl);
                            final firstLayout = _view == null;
                            final view = _view = _viewFor(image, diameter);
                            if (firstLayout) {
                              // The buttons below were built before this
                              // layout knew the circle size: enable them now.
                              WidgetsBinding.instance.addPostFrameCallback(
                                  (_) => mounted ? setState(() {}) : null);
                            }
                            final centre = area.center(Offset.zero);
                            return GestureDetector(
                              key: const ValueKey('avatar-crop-area'),
                              behavior: HitTestBehavior.opaque,
                              onScaleStart: (details) {
                                _gestureStart = _view;
                                _gestureStartFocal =
                                    details.localFocalPoint - centre;
                              },
                              onScaleUpdate: (details) {
                                final start = _gestureStart;
                                if (start == null) return;
                                setState(() => _view = start.gesture(
                                      startFocal: _gestureStartFocal,
                                      focal: details.localFocalPoint - centre,
                                      scaleFactor: details.scale,
                                      rotationDelta: details.rotation,
                                    ));
                              },
                              onScaleEnd: (_) => _gestureStart = null,
                              child: CustomPaint(
                                size: area,
                                painter: _CropPainter(
                                  image: image,
                                  view: view,
                                  ringColor: Colors.white,
                                ),
                              ),
                            );
                          }),
              ),
              _controls(strings),
            ]),
          ),
        );
      }),
    );
  }

  Widget _controls(AppStrings strings) {
    final view = _view;
    final ready = _image != null && view != null && !_failed && !_exporting;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(strings.cropHint,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70)),
        Row(children: [
          IconButton(
            tooltip: strings.cropRotate,
            onPressed: ready
                ? () => setState(() =>
                    _view = view.around(rotation: view.rotation - math.pi / 2))
                : null,
            icon: const Icon(Icons.rotate_90_degrees_ccw_outlined),
          ),
          Expanded(
            child: Slider(
              label: strings.cropZoom,
              semanticFormatterCallback: (value) =>
                  '${strings.cropZoom} ${value.toStringAsFixed(1)}x',
              min: 1,
              max: AvatarCropView.maxZoom,
              value: (view?.zoom ?? 1).clamp(1.0, AvatarCropView.maxZoom),
              onChanged: ready
                  ? (value) => setState(() => _view = view.around(zoom: value))
                  : null,
            ),
          ),
          IconButton(
            tooltip: strings.cropReset,
            onPressed: ready
                ? () => setState(() => _view = AvatarCropView(
                    imageSize: view.imageSize, diameter: view.diameter))
                : null,
            icon: const Icon(Icons.restart_alt),
          ),
        ]),
        const SizedBox(height: AppSpacing.sm),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _exporting ? null : () => Navigator.of(context).pop(),
              child: Text(strings.cancel),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: FilledButton(
              onPressed: ready ? () => unawaited(_done()) : null,
              child: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(strings.cropDone),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter({
    required this.image,
    required this.view,
    required this.ringColor,
  });

  final ui.Image image;
  final AvatarCropView view;
  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..translate(centre.dx, centre.dy);
    view.paint(canvas, image);
    canvas.restore();
    final circle = Rect.fromCircle(center: centre, radius: view.diameter / 2);
    // Dim everything outside the circle, Telegram-style.
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addOval(circle),
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );
    canvas.drawOval(
      circle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ringColor.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.view != view ||
      oldDelegate.ringColor != ringColor;
}
