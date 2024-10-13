import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_view/photo_view.dart'
    show
        PhotoViewHeroAttributes,
        PhotoViewImageScaleEndCallback,
        PhotoViewImageTapDownCallback,
        PhotoViewImageTapUpCallback,
        PhotoViewScaleState,
        ScaleStateCycle;
import 'package:photo_view/src/controller/photo_view_controller.dart';
import 'package:photo_view/src/controller/photo_view_controller_delegate.dart';
import 'package:photo_view/src/controller/photo_view_scalestate_controller.dart';
import 'package:photo_view/src/core/photo_view_gesture_detector.dart';
import 'package:photo_view/src/core/photo_view_hit_corners.dart';
import 'package:photo_view/src/utils/photo_view_utils.dart';

const _defaultDecoration = const BoxDecoration(
  color: const Color.fromRGBO(0, 0, 0, 1.0),
);

class PhotoViewCore extends StatefulWidget {
  const PhotoViewCore({
    super.key,
    required this.imageProvider,
    required this.backgroundDecoration,
    required this.semanticLabel,
    required this.gaplessPlayback,
    required this.heroAttributes,
    required this.enableRotation,
    required this.onTapUp,
    required this.onTapDown,
    required this.onScaleEnd,
    required this.gestureDetectorBehavior,
    required this.controller,
    required this.scaleBoundaries,
    required this.scaleStateCycle,
    required this.scaleStateController,
    required this.basePosition,
    required this.tightMode,
    required this.filterQuality,
    required this.disableGestures,
    required this.enablePanAlways,
    required this.strictScale,
  }) : customChild = null;

  const PhotoViewCore.customChild({
    super.key,
    required this.customChild,
    required this.backgroundDecoration,
    this.heroAttributes,
    required this.enableRotation,
    this.onTapUp,
    this.onTapDown,
    this.onScaleEnd,
    this.gestureDetectorBehavior,
    required this.controller,
    required this.scaleBoundaries,
    required this.scaleStateCycle,
    required this.scaleStateController,
    required this.basePosition,
    required this.tightMode,
    required this.filterQuality,
    required this.disableGestures,
    required this.enablePanAlways,
    required this.strictScale,
  })  : imageProvider = null,
        semanticLabel = null,
        gaplessPlayback = false;

  static const double defaultPanInertia = .2;

  final Decoration? backgroundDecoration;
  final ImageProvider? imageProvider;
  final String? semanticLabel;
  final bool? gaplessPlayback;
  final PhotoViewHeroAttributes? heroAttributes;
  final bool enableRotation;
  final Widget? customChild;

  final PhotoViewControllerBase controller;
  final PhotoViewScaleStateController scaleStateController;
  final ScaleBoundaries scaleBoundaries;
  final ScaleStateCycle scaleStateCycle;
  final Alignment basePosition;

  final PhotoViewImageTapUpCallback? onTapUp;
  final PhotoViewImageTapDownCallback? onTapDown;
  final PhotoViewImageScaleEndCallback? onScaleEnd;
  final HitTestBehavior? gestureDetectorBehavior;
  final bool tightMode;
  final bool disableGestures;
  final bool enablePanAlways;
  final bool strictScale;

  final FilterQuality filterQuality;

  @override
  State<StatefulWidget> createState() {
    return PhotoViewCoreState();
  }

  bool get hasCustomChild => customChild != null;
}

class PhotoViewCoreState extends State<PhotoViewCore>
    with
        TickerProviderStateMixin,
        PhotoViewControllerDelegate,
        HitCornersDetector {
  Offset? _startFocalPoint, _lastViewportFocalPosition;
  double? _startScale,
      _quickScaleLastY,
      _quickScaleLastDistance,
      _startRotation;
  late bool _doubleTap, _quickScaleMoved;
  DateTime _lastScaleGestureDate = DateTime.now();

  late AnimationController _scaleAnimationController;
  late Animation<double> _scaleAnimation;

  late AnimationController _positionAnimationController;
  late Animation<Offset> _positionAnimation;

  late final AnimationController _rotationAnimationController;
  late Animation<double> _rotationAnimation;

  PhotoViewHeroAttributes? get heroAttributes => widget.heroAttributes;

  ScaleBoundaries? cachedScaleBoundaries;

  static const _flingPointerKind = PointerDeviceKind.unknown;

  @override
  void initState() {
    super.initState();
    _scaleAnimationController = AnimationController(vsync: this)
      ..addListener(handleScaleAnimation)
      ..addStatusListener(onAnimationStatus);
    _positionAnimationController = AnimationController(vsync: this)
      ..addListener(handlePositionAnimate);
    _rotationAnimationController = AnimationController(vsync: this)
      ..addListener(handleRotationAnimation);

    initDelegate();
    addAnimateOnScaleStateUpdate(animateOnScaleStateUpdate);

    cachedScaleBoundaries = widget.scaleBoundaries;
    controller.scaleBoundaries = widget.scaleBoundaries;

    // force delegate scale computing on initialization
    // so that it does not happen lazily at the beginning of a scale animation
    recalcScale();
  }

  @override
  void dispose() {
    _scaleAnimationController.dispose();
    _positionAnimationController.dispose();
    _rotationAnimationController.dispose();
    super.dispose();
  }

  void handleScaleAnimation() {
    scale = _scaleAnimation.value;
  }

  void handlePositionAnimate() {
    controller.position = _positionAnimation.value;
  }

  void handleRotationAnimation() {
    controller.rotation = _rotationAnimation.value;
  }

  Stopwatch? _scaleStopwatch;
  VelocityTracker? _velocityTracker;

  void onScaleStart(ScaleStartDetails details, bool doubleTap) {
    _scaleStopwatch = Stopwatch()..start();
    _velocityTracker = VelocityTracker.withKind(_flingPointerKind);

    _startScale = scale;
    _startRotation = controller.rotation;
    _startFocalPoint = details.localFocalPoint;
    _lastViewportFocalPosition = _startFocalPoint;
    _doubleTap = doubleTap;
    _quickScaleLastDistance = null;
    _quickScaleLastY = _startFocalPoint!.dy;
    _quickScaleMoved = false;

    _scaleAnimationController.stop();
    _positionAnimationController.stop();
    _rotationAnimationController.stop();
  }

  void onScaleUpdate(ScaleUpdateDetails details) {
    final boundaries = scaleBoundaries;

    final elapsed = _scaleStopwatch?.elapsed;
    if (elapsed != null) {
      _velocityTracker?.addPosition(elapsed, details.focalPoint);
    }

    double newScale;
    if (_doubleTap) {
      // quick scale, aka one finger zoom
      // magic numbers from `davemorrissey/subsampling-scale-image-view`
      final focalPointY = details.localFocalPoint.dy;
      final distance = (focalPointY - _startFocalPoint!.dy).abs() * 2 + 20;
      _quickScaleLastDistance ??= distance;
      final spanDiff = (1 - (distance / _quickScaleLastDistance!)).abs() * .5;
      _quickScaleMoved |= spanDiff > .03;
      final factor = _quickScaleMoved
          ? (focalPointY > _quickScaleLastY! ? (1 + spanDiff) : (1 - spanDiff))
          : 1;
      _quickScaleLastDistance = distance;
      _quickScaleLastY = focalPointY;
      newScale = scale * factor;
    } else {
      newScale = _startScale! * details.scale;
    }
    if (widget.strictScale) {
      newScale = boundaries.clampScale(newScale);
    }
    newScale = max(0, newScale);
    // focal point is in viewport coordinates
    final scaleFocalPoint =
        _doubleTap ? _startFocalPoint! : details.localFocalPoint;

    final viewportCenter = boundaries.viewportCenter;
    final centerContentPosition =
        boundaries.viewportToContentPosition(controller.value, viewportCenter);
    final scalePositionDelta =
        (scaleFocalPoint - viewportCenter) * (scale / newScale - 1);
    final panPositionDelta = scaleFocalPoint - _lastViewportFocalPosition!;

    final newPosition = widget.enablePanAlways
        ? (boundaries.contentToStatePosition(newScale, centerContentPosition) +
            scalePositionDelta +
            panPositionDelta)
        : boundaries.clampPosition(
            position: boundaries.contentToStatePosition(
                    newScale, centerContentPosition) +
                scalePositionDelta +
                panPositionDelta,
            scale: newScale,
          );

    updateMultiple(
      scale: newScale,
      position: newPosition,
      rotation:
          widget.enableRotation ? _startRotation! + details.rotation : null,
      rotationFocusPoint: widget.enableRotation ? details.focalPoint : null,
    );

    _lastViewportFocalPosition = scaleFocalPoint;
  }

  void onScaleEnd(ScaleEndDetails details) {
    final boundaries = scaleBoundaries;

    final currentPosition = controller.position;
    final currentScale = controller.scale!;

    // animate back to min/max scale if gesture yielded a scale exceeding them
    final newScale = boundaries.clampScale(currentScale);
    if (currentScale != newScale) {
      final newPosition = boundaries.clampPosition(
        position: currentPosition * newScale / currentScale,
        scale: newScale,
      );
      animateScale(currentScale, newScale);
      animatePosition(currentPosition, newPosition);
      return;
    }

    // The gesture recognizer triggers a new `onScaleStart` every time a pointer/finger is added or removed.
    // Following a pinch-to-zoom gesture, a new panning gesture may start if the user does not lift both fingers at the same time,
    // so we dismiss such panning gestures when it looks like it followed a scaling gesture.
    final isPanning = currentScale == _startScale &&
        DateTime.now().difference(_lastScaleGestureDate).inMilliseconds > 100;

    // animate position only when panning without scaling
    if (isPanning) {
      final pps = details.velocity.pixelsPerSecond;
      if (pps != Offset.zero) {
        final newPosition = boundaries.clampPosition(
          position: currentPosition + pps * PhotoViewCore.defaultPanInertia,
          scale: currentScale,
        );
        if (currentPosition != newPosition) {
          final tween = Tween<Offset>(begin: currentPosition, end: newPosition);
          const curve = Curves.easeOutCubic;
          _positionAnimation = tween.animate(CurvedAnimation(
              parent: _positionAnimationController, curve: curve));
          _positionAnimationController
            ..duration = _getAnimationDurationForVelocity(
                curve: curve, tween: tween, targetPixelPerSecond: pps)
            ..forward(from: 0.0);
        }
      }
    }

    if (currentScale != _startScale) {
      _lastScaleGestureDate = DateTime.now();
    }
  }

  Duration _getAnimationDurationForVelocity({
    required Cubic curve,
    required Tween<Offset> tween,
    required Offset targetPixelPerSecond,
  }) {
    assert(targetPixelPerSecond != Offset.zero);
    // find initial animation velocity over the first 20% of the specified curve
    const t = 0.2;
    final animationVelocity =
        (tween.end! - tween.begin!).distance * curve.transform(t) / t;
    final gestureVelocity = targetPixelPerSecond.distance;
    return Duration(
        milliseconds: gestureVelocity != 0
            ? (animationVelocity / gestureVelocity * 1000).round()
            : 0);
  }

  Alignment? _getTapAlignment(Offset viewportTapPosition) {
    final boundaries = scaleBoundaries;

    final viewportSize = boundaries.outerSize;
    return Alignment(viewportTapPosition.dx / viewportSize.width,
        viewportTapPosition.dy / viewportSize.height);
  }

  Offset? _getChildTapPosition(Offset viewportTapPosition) {
    final boundaries = scaleBoundaries;

    return boundaries.viewportToContentPosition(
        controller.value, viewportTapPosition);
  }

  void _onTapUp(TapUpDetails details) {
    final onTap = widget.onTapUp;
    if (onTap == null) {
      return;
    }

    final viewportTapPosition = details.localPosition;
    final alignment = _getTapAlignment(viewportTapPosition);
    final childTapPosition = _getChildTapPosition(viewportTapPosition);
    if (alignment != null && childTapPosition != null) {
      onTap(context, details, controller.value);
    }
  }

  void _onDoubleTap(TapDownDetails details) {
    final childTapPosition = _getChildTapPosition(details.localPosition);
    if (childTapPosition != null) {
      nextScaleState(childTapPosition);
    }
  }

  void animateScale(double? from, double? to) {
    _scaleAnimation = Tween<double>(
      begin: from,
      end: to,
    ).animate(_scaleAnimationController);
    _scaleAnimationController
      ..value = 0.0
      ..fling(velocity: 0.4);
  }

  void animatePosition(Offset from, Offset to) {
    _positionAnimation = Tween<Offset>(begin: from, end: to)
        .animate(_positionAnimationController);
    _positionAnimationController
      ..value = 0.0
      ..fling(velocity: 0.4);
  }

  void animateRotation(double from, double to) {
    _rotationAnimation = Tween<double>(begin: from, end: to)
        .animate(_rotationAnimationController);
    _rotationAnimationController
      ..value = 0.0
      ..fling(velocity: 0.4);
  }

  void onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      onAnimationStatusCompleted();
    }
  }

  /// Check if scale is equal to initial after scale animation update
  void onAnimationStatusCompleted() {
    if (scaleStateController.scaleState != PhotoViewScaleState.initial &&
        scale == scaleBoundaries.initialScale) {
      scaleStateController.setInvisibly(PhotoViewScaleState.initial);
    }
  }

  void animateOnScaleStateUpdate(
    double? prevScale,
    double? nextScale,
    Offset nextPosition,
  ) {
    animateScale(prevScale, nextScale);
    animatePosition(controller.position, nextPosition);
    animateRotation(controller.rotation, 0);
  }

  @override
  Widget build(BuildContext context) {
    // Check if we need a recalc on the scale
    // if (widget.scaleBoundaries != cachedScaleBoundaries) {
    //   markNeedsScaleRecalc = true;
    //   cachedScaleBoundaries = widget.scaleBoundaries;
    //   controller.scaleBoundaries = widget.scaleBoundaries;
    // }

    return StreamBuilder(
      stream: controller.outputStateStream,
      initialData: controller.prevValue,
      builder: (
        BuildContext context,
        AsyncSnapshot<PhotoViewControllerValue> snapshot,
      ) {
        if (!snapshot.hasData) {
          return const SizedBox();
        }

        final PhotoViewControllerValue value = snapshot.data!;

        final bool useImageScale = widget.filterQuality != FilterQuality.none;

        final computedScale = useImageScale ? 1.0 : scale;

        final matrix = Matrix4.identity()
          ..translate(value.position.dx, value.position.dy)
          ..scale(computedScale)
          ..rotateZ(value.rotation);

        final Widget customChildLayout = CustomSingleChildLayout(
          delegate: _CenterWithOriginalSizeDelegate(
            scaleBoundaries.childSize,
            basePosition,
            useImageScale,
          ),
          child: _buildHero(),
        );

        final child = Container(
          constraints: widget.tightMode
              ? BoxConstraints.tight(scaleBoundaries.childSize * scale)
              : null,
          child: Center(
            child: Transform(
              child: customChildLayout,
              transform: matrix,
              alignment: basePosition,
            ),
          ),
          decoration: widget.backgroundDecoration ?? _defaultDecoration,
        );

        if (widget.disableGestures) {
          return child;
        }

        return PhotoViewGestureDetector(
          hitDetector: this,
          onScaleStart: onScaleStart,
          onScaleUpdate: onScaleUpdate,
          onScaleEnd: onScaleEnd,
          onTapUp: widget.onTapUp == null ? null : _onTapUp,
          onDoubleTap: _onDoubleTap,
          child: child,
        );
      },
    );
  }

  Widget _buildHero() {
    return heroAttributes != null
        ? Hero(
            tag: heroAttributes!.tag,
            createRectTween: heroAttributes!.createRectTween,
            flightShuttleBuilder: heroAttributes!.flightShuttleBuilder,
            placeholderBuilder: heroAttributes!.placeholderBuilder,
            transitionOnUserGestures: heroAttributes!.transitionOnUserGestures,
            child: _buildChild(),
          )
        : _buildChild();
  }

  Widget _buildChild() {
    return widget.hasCustomChild
        ? widget.customChild!
        : Image(
            image: widget.imageProvider!,
            semanticLabel: widget.semanticLabel,
            gaplessPlayback: widget.gaplessPlayback ?? false,
            filterQuality: widget.filterQuality,
            width: scaleBoundaries.childSize.width * scale,
            fit: BoxFit.contain,
          );
  }
}

class _CenterWithOriginalSizeDelegate extends SingleChildLayoutDelegate {
  const _CenterWithOriginalSizeDelegate(
    this.subjectSize,
    this.basePosition,
    this.useImageScale,
  );

  final Size subjectSize;
  final Alignment basePosition;
  final bool useImageScale;

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final childWidth = useImageScale ? childSize.width : subjectSize.width;
    final childHeight = useImageScale ? childSize.height : subjectSize.height;

    final halfWidth = (size.width - childWidth) / 2;
    final halfHeight = (size.height - childHeight) / 2;

    final double offsetX = halfWidth * (basePosition.x + 1);
    final double offsetY = halfHeight * (basePosition.y + 1);
    return Offset(offsetX, offsetY);
  }

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return useImageScale
        ? const BoxConstraints()
        : BoxConstraints.tight(subjectSize);
  }

  @override
  bool shouldRelayout(_CenterWithOriginalSizeDelegate oldDelegate) {
    return oldDelegate != this;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _CenterWithOriginalSizeDelegate &&
          runtimeType == other.runtimeType &&
          subjectSize == other.subjectSize &&
          basePosition == other.basePosition &&
          useImageScale == other.useImageScale;

  @override
  int get hashCode =>
      subjectSize.hashCode ^ basePosition.hashCode ^ useImageScale.hashCode;
}
