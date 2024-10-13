import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_view/src/core/photo_view_hit_corners.dart';
import 'package:photo_view/src/core/photo_view_scale_gesture_recognizer.dart';

class PhotoViewGestureDetector extends StatefulWidget {
  const PhotoViewGestureDetector({
    super.key,
    required this.hitDetector,
    this.onScaleStart,
    this.onScaleUpdate,
    this.onScaleEnd,
    this.onTapDown,
    this.onTapUp,
    this.onDoubleTap,
    this.behavior,
    this.child,
  });
  final HitCornersDetector? hitDetector;

  final void Function(ScaleStartDetails details, bool doubleTap)? onScaleStart;
  final GestureScaleUpdateCallback? onScaleUpdate;
  final GestureScaleEndCallback? onScaleEnd;

  final GestureTapDownCallback? onTapDown;
  final GestureTapUpCallback? onTapUp;
  final GestureTapDownCallback? onDoubleTap;

  final HitTestBehavior? behavior;
  final Widget? child;

  @override
  State<PhotoViewGestureDetector> createState() =>
      _PhotoViewGestureDetectorState();
}

class _PhotoViewGestureDetectorState extends State<PhotoViewGestureDetector> {
  final ValueNotifier<TapDownDetails?> doubleTapDetails = ValueNotifier(null);

  @override
  void dispose() {
    doubleTapDetails.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gestureSettings = MediaQuery.gestureSettingsOf(context);
    final gestures = <Type, GestureRecognizerFactory>{};

    if (widget.onTapDown != null || widget.onTapUp != null) {
      gestures[TapGestureRecognizer] =
          GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
        () => TapGestureRecognizer(debugOwner: this),
        (instance) {
          instance
            ..onTapDown = widget.onTapDown
            ..onTapUp = widget.onTapUp;
        },
      );
    }

    final scope = PhotoViewGestureDetectorScope.maybeOf(context);
    if (scope != null) {
      gestures[PhotoViewScaleGestureRecognizer] =
          GestureRecognizerFactoryWithHandlers<PhotoViewScaleGestureRecognizer>(
        () => PhotoViewScaleGestureRecognizer(
          debugOwner: this,
          scope: scope,
          doubleTapDetails: doubleTapDetails,
        ),
        (instance) {
          instance
            ..hitDetector = widget.hitDetector
            ..onStart = widget.onScaleStart != null
                ? (details) => widget.onScaleStart!(
                    details, doubleTapDetails.value != null)
                : null
            ..onUpdate = widget.onScaleUpdate
            ..onEnd = widget.onScaleEnd
            ..gestureSettings = gestureSettings;
        },
      );
    }

    gestures[DoubleTapGestureRecognizer] =
        GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
      () => DoubleTapGestureRecognizer(
        debugOwner: this,
      ),
      (instance) {
        final onDoubleTap = widget.onDoubleTap;
        instance
          ..onDoubleTapCancel = _onDoubleTapCancel
          ..onDoubleTapDown = _onDoubleTapDown
          ..onDoubleTap = onDoubleTap != null
              ? () {
                  final details = doubleTapDetails.value;
                  if (details != null) {
                    onDoubleTap(details);
                    doubleTapDetails.value = null;
                  }
                }
              : null;
      },
    );

    return RawGestureDetector(
      gestures: gestures,
      behavior: widget.behavior ?? HitTestBehavior.translucent,
      child: widget.child,
    );
  }

  void _onDoubleTapCancel() => doubleTapDetails.value = null;

  void _onDoubleTapDown(TapDownDetails details) {
    doubleTapDetails.value = details;
  }
}

class PhotoViewGestureDetectorScope extends InheritedWidget {
  const PhotoViewGestureDetectorScope({
    super.key,
    required this.axis,
    this.touchSlopFactor = .8,
    this.escapeByFling = true,
    this.acceptPointerEvent,
    required super.child,
  });
  final List<Axis> axis;

  // in [0, 1[
  // 0: most reactive but will not let tap recognizers accept gestures
  // <1: less reactive but gives the most leeway to other recognizers
  // 1: will not be able to compete with a `HorizontalDragGestureRecognizer` up the widget tree
  final double touchSlopFactor;

  // when zoomed in and hitting an edge, allow using a fling gesture to go to the previous/next page,
  // instead of yielding to the outer scrollable right away
  final bool escapeByFling;

  final bool? Function(Offset move)? acceptPointerEvent;

  static PhotoViewGestureDetectorScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<PhotoViewGestureDetectorScope>();
  }

  PhotoViewGestureDetectorScope copyWith({
    List<Axis>? axis,
    double? touchSlopFactor,
    bool? Function(Offset move)? acceptPointerEvent,
    required Widget child,
  }) {
    return PhotoViewGestureDetectorScope(
      axis: axis ?? this.axis,
      touchSlopFactor: touchSlopFactor ?? this.touchSlopFactor,
      acceptPointerEvent: acceptPointerEvent ?? this.acceptPointerEvent,
      child: child,
    );
  }

  @override
  bool updateShouldNotify(PhotoViewGestureDetectorScope oldWidget) {
    return axis != oldWidget.axis ||
        touchSlopFactor != oldWidget.touchSlopFactor ||
        acceptPointerEvent != oldWidget.acceptPointerEvent;
  }
}
