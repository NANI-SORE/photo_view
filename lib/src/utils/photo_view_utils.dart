import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:photo_view/photo_view.dart';

/// Given a [PhotoViewScaleState], returns a scale value considering [scaleBoundaries].
double getScaleForScaleState(
  PhotoViewScaleState scaleState,
  ScaleBoundaries scaleBoundaries,
) {
  switch (scaleState) {
    case PhotoViewScaleState.initial:
      return _clampSize(
        scaleBoundaries.initialScale,
        scaleBoundaries,
      );
    case PhotoViewScaleState.zoomedIn:
      return _clampSize(
        scaleBoundaries.maxScale,
        scaleBoundaries,
      );
    case PhotoViewScaleState.zoomedOut:
      return _clampSize(
        scaleBoundaries.minScale,
        scaleBoundaries,
      );
    case PhotoViewScaleState.covering:
      return _clampSize(
        _scaleForCovering(
          scaleBoundaries.outerSize,
          scaleBoundaries.childSize,
        ),
        scaleBoundaries,
      );
    case PhotoViewScaleState.originalSize:
      return _clampSize(1.0, scaleBoundaries);
    // Will never be reached
    default:
      return 0;
  }
}

/// Internal class to wraps custom scale boundaries (min, max and initial)
/// Also, stores values regarding the two sizes: the container and teh child.
class ScaleBoundaries {
  const ScaleBoundaries(
    this._minScale,
    this._maxScale,
    this._initialScale,
    this.outerSize,
    this.childSize,
  );

  final dynamic _minScale;
  final dynamic _maxScale;
  final dynamic _initialScale;
  final Size outerSize;
  final Size childSize;

  static const Alignment basePosition = Alignment.center;

  double get minScale {
    assert(_minScale is double || _minScale is PhotoViewComputedScale);
    if (_minScale == PhotoViewComputedScale.contained) {
      return _scaleForContained(outerSize, childSize) *
          (_minScale as PhotoViewComputedScale).multiplier; // ignore: avoid_as
    }
    if (_minScale == PhotoViewComputedScale.covered) {
      return coveringScale *
          (_minScale as PhotoViewComputedScale).multiplier; // ignore: avoid_as
    }
    assert(_minScale >= 0.0);
    return _minScale;
  }

  double get coveringScale {
    return _scaleForCovering(outerSize, childSize);
  }

  double get maxScale {
    assert(_maxScale is double || _maxScale is PhotoViewComputedScale);
    if (_maxScale == PhotoViewComputedScale.contained) {
      return (_scaleForContained(outerSize, childSize) *
              (_maxScale as PhotoViewComputedScale) // ignore: avoid_as
                  .multiplier)
          .clamp(minScale, double.infinity);
    }
    if (_maxScale == PhotoViewComputedScale.covered) {
      return (coveringScale *
              (_maxScale as PhotoViewComputedScale) // ignore: avoid_as
                  .multiplier)
          .clamp(minScale, double.infinity);
    }
    return (_maxScale as double).clamp(minScale, double.infinity);
  }

  double get initialScale {
    assert(_initialScale is double || _initialScale is PhotoViewComputedScale);
    if (_initialScale == PhotoViewComputedScale.contained) {
      return _scaleForContained(outerSize, childSize) *
          (_initialScale as PhotoViewComputedScale) // ignore: avoid_as
              .multiplier;
    }
    if (_initialScale == PhotoViewComputedScale.covered) {
      return coveringScale *
          (_initialScale as PhotoViewComputedScale) // ignore: avoid_as
              .multiplier;
    }
    return (_initialScale as double).clamp(minScale, maxScale);
  }

  @override
  String toString() =>
      'ScaleBoundaries(minScale: $minScale, maxScale: $maxScale, initialScale: $initialScale, outerSize: $outerSize, childSize: $childSize)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScaleBoundaries &&
          runtimeType == other.runtimeType &&
          _minScale == other._minScale &&
          _maxScale == other._maxScale &&
          _initialScale == other._initialScale &&
          outerSize == other.outerSize &&
          childSize == other.childSize;

  @override
  int get hashCode =>
      _minScale.hashCode ^
      _maxScale.hashCode ^
      _initialScale.hashCode ^
      outerSize.hashCode ^
      childSize.hashCode;

  double clampScale(double scale) {
    return scale.clamp(minScale, maxScale);
  }

  Offset clampPosition({required Offset position, required double scale}) {
    final computedWidth = childSize.width * scale;
    final computedHeight = childSize.height * scale;

    final viewportWidth = outerSize.width;
    final viewportHeight = outerSize.height;

    var finalX = 0.0;
    if (viewportWidth < computedWidth) {
      final range = getXEdges(scale: scale);
      finalX = position.dx.clamp(range.min, range.max);
    }

    var finalY = 0.0;
    if (viewportHeight < computedHeight) {
      final range = getYEdges(scale: scale);
      finalY = position.dy.clamp(range.min, range.max);
    }

    return Offset(finalX, finalY);
  }

  double get originalScale {
    final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
    return 1.0 / (view?.devicePixelRatio ?? 1.0);
  }

  Offset get viewportCenter => outerSize.center(Offset.zero);

  Offset get _contentCenter => childSize.center(Offset.zero);

  Offset viewportToContentPosition(
      PhotoViewControllerValue value, Offset viewportPosition) {
    return (viewportPosition - viewportCenter - value.position) / value.scale! +
        _contentCenter;
  }

  Offset contentToStatePosition(double scale, Offset contentPosition) {
    return (_contentCenter - contentPosition) * scale;
  }

  CornersRange getXEdges({required double scale}) {
    final computedWidth = childSize.width * scale;
    final viewportWidth = outerSize.width;

    final positionX = basePosition.x;
    final widthDiff = computedWidth - viewportWidth;

    final minX = ((positionX - 1).abs() / 2) * widthDiff * -1;
    final maxX = ((positionX + 1).abs() / 2) * widthDiff;
    return CornersRange(minX, maxX);
  }

  CornersRange getYEdges({required double scale}) {
    final computedHeight = childSize.height * scale;
    final viewportHeight = outerSize.height;

    final positionY = basePosition.y;
    final heightDiff = computedHeight - viewportHeight;

    final minY = ((positionY - 1).abs() / 2) * heightDiff * -1;
    final maxY = ((positionY + 1).abs() / 2) * heightDiff;
    return CornersRange(minY, maxY);
  }
}

double _scaleForContained(Size size, Size childSize) {
  final double imageWidth = childSize.width;
  final double imageHeight = childSize.height;

  final double screenWidth = size.width;
  final double screenHeight = size.height;

  return min(screenWidth / imageWidth, screenHeight / imageHeight);
}

double _scaleForCovering(Size size, Size childSize) {
  final double imageWidth = childSize.width;
  final double imageHeight = childSize.height;

  final double screenWidth = size.width;
  final double screenHeight = size.height;

  return max(screenWidth / imageWidth, screenHeight / imageHeight);
}

double _clampSize(double size, ScaleBoundaries scaleBoundaries) {
  return size.clamp(scaleBoundaries.minScale, scaleBoundaries.maxScale);
}

/// Simple class to store a min and a max value
class CornersRange {
  const CornersRange(this.min, this.max);
  final double min;
  final double max;

  double get diff => (max - min).abs();

  @override
  String toString() =>
      'CornersRange(min: ${min.toStringAsFixed(1)}, max: ${max.toStringAsFixed(1)}, diff: ${diff.toStringAsFixed(1)})';
}
