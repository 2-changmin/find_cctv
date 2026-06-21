import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SafeLensApp());
}

class SuspiciousBox {
  const SuspiciousBox({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.score,
    required this.confidence,
    required this.risk,
    required this.type,
    required this.reason,
    this.evidence = const {},
  });

  final int x;
  final int y;
  final int w;
  final int h;
  final double score;
  final int confidence;
  final String risk;
  final String type;
  final String reason;
  final Map<String, int> evidence;

  SuspiciousBox copyWith({
    int? x,
    int? y,
    int? w,
    int? h,
    double? score,
    int? confidence,
    String? risk,
    String? type,
    String? reason,
    Map<String, int>? evidence,
  }) {
    return SuspiciousBox(
      x: x ?? this.x,
      y: y ?? this.y,
      w: w ?? this.w,
      h: h ?? this.h,
      score: score ?? this.score,
      confidence: confidence ?? this.confidence,
      risk: risk ?? this.risk,
      type: type ?? this.type,
      reason: reason ?? this.reason,
      evidence: evidence ?? this.evidence,
    );
  }
}

double _clamp01(double value) => math.max(0, math.min(1, value)).toDouble();

String _riskFromScore(double score) {
  if (score >= 0.78) return '높음';
  if (score >= 0.62) return '주의';
  return '낮음';
}

double _colorSaturation(num r, num g, num b) {
  final maxValue = math.max(r, math.max(g, b)).toDouble();
  final minValue = math.min(r, math.min(g, b)).toDouble();
  if (maxValue == 0) return 0;
  return (maxValue - minValue) / maxValue;
}

double _aspectScore(int w, int h) {
  final aspect = w > h ? w / math.max(1, h) : h / math.max(1, w);
  return _clamp01((2.1 - aspect) / 1.1);
}

double _fillScore(double fill) {
  if (fill < 0.12) return 0;
  if (fill > 0.92) return 0.75;
  return _clamp01((fill - 0.12) / 0.48);
}

class _DetectorConfig {
  const _DetectorConfig({
    required this.local,
    required this.darkDelta,
    required this.brightDelta,
    required this.minScore,
    required this.fallbackScore,
    required this.maxOut,
  });

  final int local;
  final int darkDelta;
  final int brightDelta;
  final double minScore;
  final double fallbackScore;
  final int maxOut;

  _DetectorConfig live() {
    return _DetectorConfig(
      local: math.max(16, local - 4),
      darkDelta: math.max(12, darkDelta - 6),
      brightDelta: math.max(16, brightDelta - 8),
      minScore: minScore - 0.04,
      fallbackScore: fallbackScore - 0.04,
      maxOut: maxOut,
    );
  }
}

class _BoxStats {
  const _BoxStats({required this.mean, required this.std, required this.area});

  final double mean;
  final double std;
  final int area;
}

class _RingStats {
  const _RingStats({required this.mean, required this.std});

  final double mean;
  final double std;
}

class _RadialStats {
  const _RadialStats({
    required this.center,
    required this.ring,
    required this.contrast,
    required this.brightRatio,
    required this.compactHighlight,
  });

  final double center;
  final double ring;
  final double contrast;
  final double brightRatio;
  final double compactHighlight;
}

class _FlashDeltaStats {
  const _FlashDeltaStats(
      {required this.score,
      required this.mean,
      required this.peak,
      required this.hotRatio});

  final double score;
  final double mean;
  final double peak;
  final double hotRatio;
}

class _Spot {
  _Spot({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.x1,
    required this.y1,
    required this.cx,
    required this.cy,
    required this.count,
    required this.area,
    required this.fill,
    required this.mean,
    required this.sat,
    required this.kind,
    required this.shape,
  });

  final int x;
  final int y;
  final int w;
  final int h;
  final int x1;
  final int y1;
  final double cx;
  final double cy;
  final int count;
  final int area;
  final double fill;
  final double mean;
  final double sat;
  final String kind;
  final double shape;
}

class _ScanCluster {
  _ScanCluster(SuspiciousBox box, int frameIndex)
      : cx = box.x + box.w / 2,
        cy = box.y + box.h / 2,
        count = 1,
        sumX = box.x,
        sumY = box.y,
        sumW = box.w,
        sumH = box.h,
        w = box.w,
        h = box.h,
        best = box,
        bestConfidence = box.confidence,
        sumConfidence = box.confidence,
        framesSeen = {frameIndex};

  double cx;
  double cy;
  int count;
  int sumX;
  int sumY;
  int sumW;
  int sumH;
  int w;
  int h;
  SuspiciousBox best;
  int bestConfidence;
  int sumConfidence;
  final Set<int> framesSeen;

  void add(SuspiciousBox box, int frameIndex) {
    count += 1;
    sumX += box.x;
    sumY += box.y;
    sumW += box.w;
    sumH += box.h;
    cx = sumX / count + sumW / count / 2;
    cy = sumY / count + sumH / count / 2;
    framesSeen.add(frameIndex);
    sumConfidence += box.confidence;
    if (box.confidence > bestConfidence) {
      best = box;
      bestConfidence = box.confidence;
    }
  }
}

List<SuspiciousBox> detectSuspiciousSpots(
  img.Image source, {
  int? maxResults,
  int minConfidence = 0,
  bool liveMode = false,
  String sensitivity = 'normal',
  img.Image? previousImage,
}) {
  final width = source.width;
  final height = source.height;
  final total = width * height;
  final lum = Float32List(total);
  final sat = Float32List(total);
  final previousMatches = previousImage != null &&
      previousImage.width == width &&
      previousImage.height == height;
  final positiveDiff = previousMatches ? Float32List(total) : null;
  var globalDeltaSum = 0.0;

  for (var i = 0; i < total; i += 1) {
    final x = i % width;
    final y = i ~/ width;
    final pixel = source.getPixel(x, y);
    final r = pixel.r;
    final g = pixel.g;
    final b = pixel.b;
    final value = r * 0.299 + g * 0.587 + b * 0.114;
    lum[i] = value.toDouble();
    sat[i] = _colorSaturation(r, g, b);

    if (positiveDiff != null) {
      final previous = previousImage!.getPixel(x, y);
      final previousLum =
          previous.r * 0.299 + previous.g * 0.587 + previous.b * 0.114;
      final delta = value - previousLum;
      positiveDiff[i] = delta.toDouble();
      globalDeltaSum += delta;
    }
  }

  if (positiveDiff != null) {
    final globalDelta = globalDeltaSum / math.max(1, total);
    for (var i = 0; i < total; i += 1) {
      final normalized = positiveDiff[i] - globalDelta;
      positiveDiff[i] = normalized > 6 ? normalized : 0;
    }
  }

  final baseConfig = switch (sensitivity) {
    'low' => const _DetectorConfig(
        local: 30,
        darkDelta: 34,
        brightDelta: 42,
        minScore: 0.66,
        fallbackScore: 0.6,
        maxOut: 3,
      ),
    'high' => const _DetectorConfig(
        local: 22,
        darkDelta: 16,
        brightDelta: 22,
        minScore: 0.5,
        fallbackScore: 0.44,
        maxOut: 5,
      ),
    _ => const _DetectorConfig(
        local: 26,
        darkDelta: 24,
        brightDelta: 30,
        minScore: 0.58,
        fallbackScore: 0.52,
        maxOut: 4,
      ),
  };
  final threshold = liveMode ? baseConfig.live() : baseConfig;

  final integral = Float64List((width + 1) * (height + 1));
  final integralSq = Float64List((width + 1) * (height + 1));
  for (var y = 0; y < height; y += 1) {
    var row = 0.0;
    var rowSq = 0.0;
    for (var x = 0; x < width; x += 1) {
      final value = lum[y * width + x];
      row += value;
      rowSq += value * value;
      final dst = (y + 1) * (width + 1) + x + 1;
      integral[dst] = integral[y * (width + 1) + x + 1] + row;
      integralSq[dst] = integralSq[y * (width + 1) + x + 1] + rowSq;
    }
  }

  _BoxStats boxStats(num x0, num y0, num x1, num y1) {
    final ax = math.max(0, math.min(width - 1, x0.floor()));
    final ay = math.max(0, math.min(height - 1, y0.floor()));
    final bx = math.max(0, math.min(width - 1, x1.ceil()));
    final by = math.max(0, math.min(height - 1, y1.ceil()));
    final stride = width + 1;
    final area = math.max(1, (bx - ax + 1) * (by - ay + 1));
    final sum = integral[(by + 1) * stride + bx + 1] -
        integral[ay * stride + bx + 1] -
        integral[(by + 1) * stride + ax] +
        integral[ay * stride + ax];
    final sumSq = integralSq[(by + 1) * stride + bx + 1] -
        integralSq[ay * stride + bx + 1] -
        integralSq[(by + 1) * stride + ax] +
        integralSq[ay * stride + ax];
    final mean = sum / area;
    return _BoxStats(
        mean: mean,
        std: math.sqrt(math.max(0, sumSq / area - mean * mean)),
        area: area);
  }

  double localMean(int x, int y, int radius) =>
      boxStats(x - radius, y - radius, x + radius, y + radius).mean;

  final darkMask = Uint8List(total);
  final brightMask = Uint8List(total);
  final glassMask = Uint8List(total);
  final localRadius = math.max(14,
      math.min(liveMode ? 26 : 48, (math.min(width, height) * 0.04).round()));

  for (var i = 0; i < total; i += 1) {
    final x = i % width;
    final y = i ~/ width;
    final value = lum[i];
    final mean = localMean(x, y, localRadius);
    final darkDelta = mean - value;
    final brightDelta = value - mean;

    if (value <= 72 || (value <= 150 && darkDelta >= threshold.darkDelta)) {
      darkMask[i] = 1;
    }
    if (value >= 232 ||
        (value >= 175 &&
            brightDelta >= threshold.brightDelta &&
            sat[i] < 0.62)) {
      brightMask[i] = 1;
    }
    if (value >= 115 &&
        value <= 245 &&
        brightDelta.abs() >= threshold.brightDelta * 0.55 &&
        sat[i] < 0.82) {
      glassMask[i] = 1;
    }
  }

  _Spot? walk(int start, Uint8List mask, Uint8List visited, String kind) {
    final queue = <int>[start];
    visited[start] = 1;
    var minX = width;
    var minY = height;
    var maxX = 0;
    var maxY = 0;
    var count = 0;
    var sum = 0.0;
    var satSum = 0.0;

    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      final x = cur % width;
      final y = cur ~/ width;
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
      count += 1;
      sum += lum[cur];
      satSum += sat[cur];

      for (final next in [cur - 1, cur + 1, cur - width, cur + width]) {
        if (next < 0 || next >= total) continue;
        if (((next % width) - x).abs() > 1) continue;
        if (mask[next] == 0 || visited[next] == 1) continue;
        visited[next] = 1;
        queue.add(next);
      }
    }

    final spotWidth = maxX - minX + 1;
    final spotHeight = maxY - minY + 1;
    final area = spotWidth * spotHeight;
    final fill = count / math.max(1, area);
    final shape =
        _aspectScore(spotWidth, spotHeight) * 0.72 + _fillScore(fill) * 0.28;
    if (count < 3 || fill < 0.08 || shape < 0.24) return null;

    return _Spot(
      x: minX,
      y: minY,
      w: spotWidth,
      h: spotHeight,
      x1: maxX,
      y1: maxY,
      cx: minX + spotWidth / 2,
      cy: minY + spotHeight / 2,
      count: count,
      area: area,
      fill: fill,
      mean: sum / math.max(1, count),
      sat: satSum / math.max(1, count),
      kind: kind,
      shape: shape,
    );
  }

  List<_Spot> collectSpots(Uint8List mask, String kind) {
    final visited = Uint8List(total);
    final spots = <_Spot>[];
    final maxSide = liveMode ? 86 : 132;
    final maxArea = liveMode ? 3200 : 7200;

    for (var i = 0; i < total; i += 1) {
      if (mask[i] == 0 || visited[i] == 1) continue;
      final spot = walk(i, mask, visited, kind);
      if (spot == null) continue;
      if (spot.w > maxSide || spot.h > maxSide || spot.area > maxArea) continue;
      spots.add(spot);
    }
    return spots;
  }

  final rawSpots = <_Spot>[
    ...collectSpots(darkMask, 'dark'),
    ...collectSpots(brightMask, 'bright'),
    ...collectSpots(glassMask, 'glass'),
  ];

  _RingStats ringStats(_Spot spot, [int pad = 8]) {
    final outer =
        boxStats(spot.x - pad, spot.y - pad, spot.x1 + pad, spot.y1 + pad);
    final inner = boxStats(spot.x, spot.y, spot.x1, spot.y1);
    final ringArea = math.max(1, outer.area - inner.area);
    final ringMean =
        (outer.mean * outer.area - inner.mean * inner.area) / ringArea;
    return _RingStats(mean: ringMean, std: outer.std);
  }

  _RadialStats radialStats(_Spot spot) {
    final radius = math
        .max(4, math.min(liveMode ? 38 : 62, math.max(spot.w, spot.h) / 2))
        .toDouble();
    var innerSum = 0.0;
    var innerCount = 0;
    var ringSum = 0.0;
    var ringCount = 0;
    var brightCount = 0;
    var coreBrightCount = 0;
    var outerBrightCount = 0;
    final outer = (radius * 1.85).ceil();

    for (var y = math.max(0, (spot.cy - outer).floor());
        y <= math.min(height - 1, (spot.cy + outer).ceil());
        y += 1) {
      for (var x = math.max(0, (spot.cx - outer).floor());
          x <= math.min(width - 1, (spot.cx + outer).ceil());
          x += 1) {
        final dist =
            math.sqrt(math.pow(x - spot.cx, 2) + math.pow(y - spot.cy, 2));
        final value = lum[y * width + x];
        if (dist <= radius * 0.55) {
          innerSum += value;
          innerCount += 1;
          if (value >= 218) coreBrightCount += 1;
        } else if (dist <= radius * 1.85) {
          ringSum += value;
          ringCount += 1;
          if (value >= 218) outerBrightCount += 1;
        }
        if (dist <= radius * 1.85 && value >= 210) brightCount += 1;
      }
    }

    final coreBrightRatio = innerCount > 0 ? coreBrightCount / innerCount : 0.0;
    final outerBrightRatio = ringCount > 0 ? outerBrightCount / ringCount : 0.0;
    final center = innerCount > 0 ? innerSum / innerCount : spot.mean;
    final ring = ringCount > 0 ? ringSum / ringCount : spot.mean;
    return _RadialStats(
      center: center,
      ring: ring,
      contrast: (ring - center).abs(),
      brightRatio: innerCount + ringCount > 0
          ? brightCount / (innerCount + ringCount)
          : 0,
      compactHighlight:
          _clamp01((coreBrightRatio - outerBrightRatio + 0.03) / 0.18),
    );
  }

  _FlashDeltaStats flashDeltaStats(_Spot spot) {
    if (positiveDiff == null) {
      return const _FlashDeltaStats(score: 0, mean: 0, peak: 0, hotRatio: 0);
    }
    final radius = math
        .max(4, math.min(liveMode ? 42 : 64, math.max(spot.w, spot.h) * 0.85))
        .toDouble();
    var sum = 0.0;
    var count = 0;
    var hot = 0;
    var peak = 0.0;

    for (var y = math.max(0, (spot.cy - radius).floor());
        y <= math.min(height - 1, (spot.cy + radius).ceil());
        y += 1) {
      for (var x = math.max(0, (spot.cx - radius).floor());
          x <= math.min(width - 1, (spot.cx + radius).ceil());
          x += 1) {
        final dist =
            math.sqrt(math.pow(x - spot.cx, 2) + math.pow(y - spot.cy, 2));
        if (dist > radius) continue;
        final delta = positiveDiff[y * width + x];
        sum += delta;
        count += 1;
        if (delta >= 24) hot += 1;
        peak = math.max(peak, delta);
      }
    }

    final mean = count > 0 ? sum / count : 0.0;
    final hotRatio = count > 0 ? hot / count : 0.0;
    return _FlashDeltaStats(
      mean: mean,
      peak: peak,
      hotRatio: hotRatio,
      score: _clamp01(mean / 28) * 0.45 +
          _clamp01(peak / 70) * 0.35 +
          _clamp01(hotRatio / 0.16) * 0.2,
    );
  }

  double sampleLum(num x, num y) {
    final sx = math.max(0, math.min(width - 1, x.round()));
    final sy = math.max(0, math.min(height - 1, y.round()));
    return lum[sy * width + sx];
  }

  double radialSymmetryScore(_Spot spot) {
    final radius = math
        .max(4, math.min(liveMode ? 36 : 58, math.max(spot.w, spot.h) * 0.58))
        .toDouble();
    final samples = <double>[];
    const pairs = 12;
    for (var i = 0; i < pairs; i += 1) {
      final angle = math.pi * 2 * i / pairs;
      samples.add(sampleLum(spot.cx + math.cos(angle) * radius,
          spot.cy + math.sin(angle) * radius));
    }
    final mean = samples.reduce((acc, value) => acc + value) / samples.length;
    final variance = samples.reduce(
            (acc, value) => acc + math.pow(value - mean, 2).toDouble()) /
        samples.length;
    final std = math.sqrt(variance);
    var pairDiff = 0.0;
    for (var i = 0; i < pairs ~/ 2; i += 1) {
      pairDiff += (samples[i] - samples[i + pairs ~/ 2]).abs();
    }
    final oppositeScore = _clamp01(1 - pairDiff / (pairs * 24));
    final evennessScore = _clamp01(1 - std / 46);
    return evennessScore * 0.58 + oppositeScore * 0.42;
  }

  double glarePenalty(_Spot spot, _RadialStats radial) {
    final diameter = math.max(spot.w, spot.h);
    final largeBrightPatch = spot.kind != 'dark' &&
        diameter > (liveMode ? 34 : 48) &&
        spot.fill > 0.58;
    final broadHighlight = radial.brightRatio > 0.34;
    return (largeBrightPatch ? 0.18 : 0) + (broadHighlight ? 0.14 : 0);
  }

  double linePenalty(_Spot spot) {
    const pad = 6;
    final x0 = math.max(0, spot.x - pad);
    final y0 = math.max(0, spot.y - pad);
    final x1 = math.min(width - 1, spot.x1 + pad);
    final y1 = math.min(height - 1, spot.y1 + pad);
    var strongRows = 0;
    var strongCols = 0;

    for (var y = y0; y <= y1; y += 1) {
      var hits = 0;
      for (var x = x0; x <= x1; x += 1) {
        final value = lum[y * width + x];
        if (value < 88 || value > 220) hits += 1;
      }
      if (hits / math.max(1, x1 - x0 + 1) > 0.72) strongRows += 1;
    }

    for (var x = x0; x <= x1; x += 1) {
      var hits = 0;
      for (var y = y0; y <= y1; y += 1) {
        final value = lum[y * width + x];
        if (value < 88 || value > 220) hits += 1;
      }
      if (hits / math.max(1, y1 - y0 + 1) > 0.72) strongCols += 1;
    }

    return _clamp01((math.max(strongRows, strongCols) - 1) / 5);
  }

  double repeatedPenalty(_Spot spot) {
    final similar = rawSpots.where((other) {
      if (identical(other, spot) || other.kind != spot.kind) return false;
      final dist = math.sqrt(
          math.pow(spot.cx - other.cx, 2) + math.pow(spot.cy - other.cy, 2));
      if (dist > 120) return false;
      final sizeRatio = math.max(spot.area, other.area) /
          math.max(1, math.min(spot.area, other.area));
      return sizeRatio < 2.4;
    }).length;
    return _clamp01(similar / 5);
  }

  double edgePenalty(_Spot spot) {
    final margin = math.min(math.min(spot.x, spot.y),
        math.min(width - 1 - spot.x1, height - 1 - spot.y1));
    return margin >= 8 ? 0 : (8 - margin) / 24;
  }

  double nearestEvidence(_Spot spot, List<String> kinds) {
    var best = 0.0;
    for (final other in rawSpots) {
      if (identical(other, spot) || !kinds.contains(other.kind)) continue;
      final dist = math.sqrt(
          math.pow(spot.cx - other.cx, 2) + math.pow(spot.cy - other.cy, 2));
      final radius = math.max(
          22,
          math.min(
              liveMode ? 70 : 110,
              math.max(math.max(spot.w, spot.h), math.max(other.w, other.h)) *
                      2.2 +
                  18));
      if (dist > radius) continue;
      final sizeRatio = math.max(spot.area, other.area) /
          math.max(1, math.min(spot.area, other.area));
      if (sizeRatio > 10) continue;
      best = math.max(
          best,
          _clamp01(1 - dist / radius) * 0.65 +
              other.shape * 0.25 +
              _clamp01(other.count / 120) * 0.1);
    }
    return best;
  }

  SuspiciousBox verifyLensCandidate(_Spot spot) {
    final ring = ringStats(spot,
        math.max(6, math.min(18, (math.max(spot.w, spot.h) * 0.35).round())));
    final radial = radialStats(spot);
    final flashDelta = flashDeltaStats(spot);
    final symmetryScore = radialSymmetryScore(spot);
    final localContrast = (spot.mean - ring.mean).abs();
    final diameter = math.max(spot.w, spot.h);
    final minDiameter = liveMode ? 3 : 4;
    final maxDiameter = liveMode ? 86 : 132;
    final sizeScore = _clamp01((diameter - minDiameter) / 18) *
        _clamp01((maxDiameter - diameter) / maxDiameter + 0.5);
    final contrastScore =
        _clamp01(math.max(localContrast, radial.contrast) / 65);
    final highlightScore = spot.kind == 'bright' || spot.kind == 'glass'
        ? _clamp01((spot.mean - ring.mean + 22) / 95)
        : radial.brightRatio > 0.018
            ? 0.28
            : 0.0;
    final darkCoreScore = spot.kind == 'dark'
        ? _clamp01((ring.mean - spot.mean + 18) / 85)
        : nearestEvidence(spot, ['dark']) * 0.42;
    final companionScore = spot.kind == 'dark'
        ? nearestEvidence(spot, ['bright', 'glass'])
        : nearestEvidence(spot, ['dark', 'bright', 'glass']);
    final retroReflectionScore =
        math.max(radial.compactHighlight, flashDelta.score);
    final artifactPenalty = linePenalty(spot) * 0.24 +
        repeatedPenalty(spot) * 0.26 +
        edgePenalty(spot) * 0.22 +
        glarePenalty(spot, radial) +
        _clamp01(ring.std / 150) * 0.06;

    final evidenceFlags = [
      spot.shape >= 0.54,
      symmetryScore >= 0.5,
      contrastScore >= 0.38,
      retroReflectionScore >= 0.34,
      darkCoreScore >= 0.28,
      companionScore >= 0.26,
    ];
    final evidenceCount = evidenceFlags.where((flag) => flag).length;
    final strongOpticalEvidence =
        (retroReflectionScore >= 0.62 && spot.shape >= 0.48) ||
            (darkCoreScore >= 0.52 && contrastScore >= 0.42) ||
            (companionScore >= 0.46 && contrastScore >= 0.38);
    final requiredEvidence = sensitivity == 'high' ? 2 : 3;
    final crossCheckPenalty =
        evidenceCount >= requiredEvidence || strongOpticalEvidence
            ? 0.0
            : 0.16 + (requiredEvidence - evidenceCount) * 0.08;

    final score = _clamp01(0.14 +
        spot.shape * 0.18 +
        symmetryScore * 0.1 +
        sizeScore * 0.12 +
        contrastScore * 0.16 +
        highlightScore * 0.12 +
        darkCoreScore * 0.12 +
        companionScore * 0.1 +
        retroReflectionScore * 0.12 -
        artifactPenalty -
        crossCheckPenalty);

    var type = '렌즈 후보';
    var reason = '원형 형태와 주변 대비가 렌즈 패턴과 유사함';
    if (spot.kind == 'dark') {
      type = companionScore > 0.22 ? '렌즈 코어 의심' : '어두운 렌즈 후보';
      reason = companionScore > 0.22
          ? '어두운 코어와 가까운 반사/유리면 후보가 함께 확인됨'
          : '주변보다 어두운 원형 렌즈 후보';
    } else if (spot.kind == 'bright') {
      type = '렌즈 반사 의심';
      reason = flashDelta.score > 0.28
          ? '프레임 간 밝기 증분이 큰 원형 반사 후보'
          : '강한 반사와 원형 렌즈 표면 후보';
    } else if (spot.kind == 'glass') {
      type = '렌즈 표면 의심';
      reason = '빛을 받은 유리면/코팅 반사 후보';
    }

    final confidence = (score * 100).round();
    return SuspiciousBox(
      x: spot.x,
      y: spot.y,
      w: spot.w,
      h: spot.h,
      score: score,
      confidence: confidence,
      risk: _riskFromScore(score),
      type: type,
      reason: reason,
      evidence: {
        'shape': (spot.shape * 100).round(),
        'symmetry': (symmetryScore * 100).round(),
        'contrast': (contrastScore * 100).round(),
        'retroReflection': (retroReflectionScore * 100).round(),
        'darkCore': (darkCoreScore * 100).round(),
        'companion': (companionScore * 100).round(),
        'crossChecks': evidenceCount,
      },
    );
  }

  final verified = rawSpots.map(verifyLensCandidate).where((spot) {
    final crossChecks = spot.evidence['crossChecks'] ?? 0;
    final retroReflection = spot.evidence['retroReflection'] ?? 0;
    return spot.score >= threshold.fallbackScore &&
        (crossChecks >= (sensitivity == 'high' ? 2 : 3) ||
            retroReflection >= 62);
  }).toList()
    ..sort((a, b) => b.score.compareTo(a.score));

  final merged = <SuspiciousBox>[];
  for (final spot in verified) {
    final duplicateIndex = merged.indexWhere((previous) {
      final prevCx = previous.x + previous.w / 2;
      final prevCy = previous.y + previous.h / 2;
      final cx = spot.x + spot.w / 2;
      final cy = spot.y + spot.h / 2;
      final dist =
          math.sqrt(math.pow(prevCx - cx, 2) + math.pow(prevCy - cy, 2));
      return dist < math.max(14, math.min(previous.w, spot.w) * 0.55);
    });
    if (duplicateIndex == -1) {
      merged.add(spot);
    } else if (spot.score > merged[duplicateIndex].score) {
      merged[duplicateIndex] = spot;
    }
  }

  final strong =
      merged.where((spot) => spot.score >= threshold.minScore).toList();
  final fallback = strong.isNotEmpty ? strong : merged;
  final results = fallback
      .where((item) => item.confidence >= minConfidence)
      .toList()
    ..sort((a, b) => b.score.compareTo(a.score));
  if (maxResults == null) {
    return results;
  }
  final limit = liveMode ? math.min(maxResults, threshold.maxOut) : maxResults;
  return results.take(limit).toList();
}

class SafeLensApp extends StatelessWidget {
  const SafeLensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SafeLens',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _Palette.bg,
        colorScheme: ColorScheme.fromSeed(seedColor: _Palette.primary),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: _Palette.text,
          contentTextStyle:
              TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      home: const SafeLensHome(),
    );
  }
}

class _Palette {
  static const bg = Color(0xfff6f7fb);
  static const surface = Color(0xffffffff);
  static const surfaceMuted = Color(0xfff1f4f8);
  static const line = Color(0xffe3e7ee);
  static const text = Color(0xff111827);
  static const subText = Color(0xff6b7280);
  static const primary = Color(0xff2563eb);
  static const primarySoft = Color(0xffeaf1ff);
  static const danger = Color(0xffef4444);
}

Color _riskColor(String risk) {
  return switch (risk) {
    '높음' => _Palette.danger,
    '주의' => const Color(0xfff59e0b),
    _ => const Color(0xff38bdf8),
  };
}

class SafeLensHome extends StatefulWidget {
  const SafeLensHome({super.key});

  @override
  State<SafeLensHome> createState() => _SafeLensHomeState();
}

class _SafeLensHomeState extends State<SafeLensHome> {
  final _picker = ImagePicker();
  final _timeController = TextEditingController();
  final _placeController = TextEditingController();
  final _descController = TextEditingController();
  final _reportController = TextEditingController();

  static const _detectorSensitivity = 'normal';
  static const _photoMinConfidence = 70;
  static const _liveMinConfidence = 40;

  int _tab = 0;
  ui.Image? _previewImage;
  img.Image? _analysisImage;
  List<SuspiciousBox> _boxes = [];
  CameraController? _cameraController;
  List<SuspiciousBox> _liveBoxes = [];
  Size? _liveSourceSize;
  img.Image? _lastLiveAnalysisImage;
  img.Image? _flashOffImage;
  final List<List<SuspiciousBox>> _scanHistory = [];
  String _flashPhase = 'captureOff';
  bool _cameraOn = false;
  bool _torchOn = false;
  bool _flashDiffEnabled = false;
  bool _processingFrame = false;
  DateTime? _lastFrameScanAt;
  int _selectedHour = 0;
  int _selectedMinute = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedHour = now.hour;
    _selectedMinute = (now.minute ~/ 5) * 5;
    _syncSelectedTimeToText();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _timeController.dispose();
    _placeController.dispose();
    _descController.dispose();
    _reportController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return;
    final resized =
        decoded.width > 900 ? img.copyResize(decoded, width: 900) : decoded;
    final codec = await ui
        .instantiateImageCodec(Uint8List.fromList(img.encodePng(resized)));
    final frame = await codec.getNextFrame();
    setState(() {
      _analysisImage = resized;
      _previewImage = frame.image;
      _boxes = [];
    });
  }

  void _analyzeImage() {
    final image = _analysisImage;
    if (image == null) return;
    setState(
      () => _boxes = detectSuspiciousSpots(
        image,
        sensitivity: _detectorSensitivity,
        minConfidence: _photoMinConfidence,
      ),
    );
  }

  void _syncSelectedTimeToText() {
    final hour = _selectedHour.toString().padLeft(2, '0');
    final minute = _selectedMinute.toString().padLeft(2, '0');
    _timeController.text = '$hour:$minute';
  }

  void _onHourChanged(int? value) {
    if (value == null) return;
    setState(() {
      _selectedHour = value;
      if (_selectedHour == 24) {
        _selectedMinute = 0;
      }
      _syncSelectedTimeToText();
    });
  }

  void _onMinuteChanged(int? value) {
    if (value == null) return;
    setState(() {
      _selectedMinute = value;
      _syncSelectedTimeToText();
    });
  }

  Future<void> _startCamera() async {
    try {
      final cameras = await availableCameras();
      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller =
          CameraController(camera, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      var flashDiffEnabled = false;
      try {
        await controller.setFlashMode(FlashMode.off);
        flashDiffEnabled = true;
      } catch (_) {
        flashDiffEnabled = false;
      }
      setState(() {
        _cameraController = controller;
        _cameraOn = true;
        _liveBoxes = [];
        _liveSourceSize = null;
        _lastLiveAnalysisImage = null;
        _flashOffImage = null;
        _scanHistory.clear();
        _flashPhase = 'captureOff';
        _flashDiffEnabled = flashDiffEnabled;
        _processingFrame = false;
        _lastFrameScanAt = null;
        _torchOn = false;
      });
      try {
        await controller.startImageStream(_handleCameraImage);
      } catch (_) {
        _showMessage('실시간 의심 지점 표시는 현재 카메라에서 지원되지 않습니다.');
      }
    } catch (_) {
      _showMessage('카메라 권한 또는 장치 상태를 확인해주세요.');
    }
  }

  Future<void> _stopCamera() async {
    final controller = _cameraController;
    if (controller != null && controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
    await controller?.dispose();
    setState(() {
      _cameraController = null;
      _liveBoxes = [];
      _liveSourceSize = null;
      _lastLiveAnalysisImage = null;
      _flashOffImage = null;
      _scanHistory.clear();
      _flashPhase = 'captureOff';
      _flashDiffEnabled = false;
      _processingFrame = false;
      _lastFrameScanAt = null;
      _cameraOn = false;
      _torchOn = false;
    });
  }

  void _handleCameraImage(CameraImage frame) {
    final now = DateTime.now();
    final lastScan = _lastFrameScanAt;
    if (_processingFrame ||
        (lastScan != null && now.difference(lastScan).inMilliseconds < 600)) {
      return;
    }
    _processingFrame = true;
    _lastFrameScanAt = now;
    _processCameraImage(frame);
  }

  Future<void> _processCameraImage(CameraImage frame) async {
    try {
      final image = _cameraImageToAnalysisImage(frame);
      if (image == null) return;

      List<SuspiciousBox> nextBoxes;
      if (_flashDiffEnabled) {
        if (_flashPhase == 'captureOff') {
          _flashOffImage = image;
          _flashPhase = 'captureOn';
          try {
            await _cameraController?.setFlashMode(FlashMode.torch);
            if (mounted) setState(() => _torchOn = true);
          } catch (_) {
            _flashDiffEnabled = false;
            _lastLiveAnalysisImage = image;
          }
          return;
        }

        nextBoxes = detectSuspiciousSpots(
          image,
          maxResults: 5,
          minConfidence: _liveMinConfidence,
          liveMode: true,
          sensitivity: _detectorSensitivity,
          previousImage: _flashOffImage,
        );
        _flashOffImage = null;
        _flashPhase = 'captureOff';
        try {
          await _cameraController?.setFlashMode(FlashMode.off);
          if (mounted) setState(() => _torchOn = false);
        } catch (_) {
          _flashDiffEnabled = false;
        }
      } else {
        nextBoxes = detectSuspiciousSpots(
          image,
          maxResults: 5,
          minConfidence: _liveMinConfidence,
          liveMode: true,
          sensitivity: _detectorSensitivity,
          previousImage: _lastLiveAnalysisImage,
        );
        _lastLiveAnalysisImage = image;
      }

      final stableBoxes = _mergeScanFrames(nextBoxes);
      if (!mounted) return;
      setState(() {
        _liveBoxes = stableBoxes;
        _liveSourceSize = Size(image.width.toDouble(), image.height.toDouble());
      });
    } finally {
      _processingFrame = false;
    }
  }

  List<SuspiciousBox> _mergeScanFrames(List<SuspiciousBox> nextBoxes) {
    _scanHistory.add(nextBoxes);
    if (_scanHistory.length > 6) {
      _scanHistory.removeAt(0);
    }
    if (_scanHistory.length < 2) {
      return [];
    }

    final frames = _scanHistory.length > 5
        ? _scanHistory.sublist(_scanHistory.length - 5)
        : List<List<SuspiciousBox>>.from(_scanHistory);
    final clusters = <_ScanCluster>[];

    for (var frameIndex = 0; frameIndex < frames.length; frameIndex += 1) {
      for (final box in frames[frameIndex]) {
        final cx = box.x + box.w / 2;
        final cy = box.y + box.h / 2;
        _ScanCluster? match;
        for (final cluster in clusters) {
          final dist = math.sqrt(
            math.pow(cluster.cx - cx, 2) + math.pow(cluster.cy - cy, 2),
          );
          final sizeMatch =
              (cluster.w - box.w).abs() < math.max(20, cluster.w * 0.4) &&
                  (cluster.h - box.h).abs() < math.max(20, cluster.h * 0.4);
          if (dist < math.max(30, math.min(cluster.w, box.w) * 0.35) &&
              sizeMatch) {
            match = cluster;
            break;
          }
        }

        if (match == null) {
          clusters.add(_ScanCluster(box, frameIndex));
        } else {
          match.add(box, frameIndex);
        }
      }
    }

    final minFrameCount = math.max(2, (frames.length * 0.45).ceil());
    final merged = clusters
        .where((cluster) => cluster.framesSeen.length >= minFrameCount)
        .map((cluster) {
      final persistence = cluster.framesSeen.length / frames.length;
      final averageConfidence =
          cluster.sumConfidence / math.max(1, cluster.count);
      final confidence = math
          .min(
            99,
            cluster.bestConfidence * 0.72 +
                averageConfidence * 0.18 +
                persistence * 10,
          )
          .round();
      return cluster.best.copyWith(
        x: (cluster.sumX / cluster.count).round(),
        y: (cluster.sumY / cluster.count).round(),
        w: (cluster.sumW / cluster.count).round(),
        h: (cluster.sumH / cluster.count).round(),
        score: confidence / 100,
        confidence: confidence,
        risk: _riskFromScore(confidence / 100),
        evidence: {
          ...cluster.best.evidence,
          'persistence': (persistence * 100).round(),
        },
      );
    }).toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    return merged;
  }

  img.Image? _cameraImageToAnalysisImage(CameraImage frame) {
    return switch (frame.format.group) {
      ImageFormatGroup.yuv420 => _yPlaneToAnalysisImage(frame),
      ImageFormatGroup.bgra8888 => _bgraToAnalysisImage(frame),
      _ => null,
    };
  }

  img.Image _yPlaneToAnalysisImage(CameraImage frame) {
    final plane = frame.planes.first;
    final sampleStep = math.max(1, (frame.width / 360).ceil());
    final width = frame.width ~/ sampleStep;
    final height = frame.height ~/ sampleStep;
    final output = img.Image(width: width, height: height);

    for (var y = 0; y < height; y += 1) {
      final sourceY = y * sampleStep;
      for (var x = 0; x < width; x += 1) {
        final sourceX = x * sampleStep;
        final value = plane.bytes[sourceY * plane.bytesPerRow + sourceX];
        output.setPixelRgb(x, y, value, value, value);
      }
    }

    return output;
  }

  img.Image _bgraToAnalysisImage(CameraImage frame) {
    final plane = frame.planes.first;
    final bytesPerPixel = plane.bytesPerPixel ?? 4;
    final sampleStep = math.max(1, (frame.width / 360).ceil());
    final width = frame.width ~/ sampleStep;
    final height = frame.height ~/ sampleStep;
    final output = img.Image(width: width, height: height);

    for (var y = 0; y < height; y += 1) {
      final sourceY = y * sampleStep;
      for (var x = 0; x < width; x += 1) {
        final sourceX = x * sampleStep;
        final offset = sourceY * plane.bytesPerRow + sourceX * bytesPerPixel;
        final blue = plane.bytes[offset];
        final green = plane.bytes[offset + 1];
        final red = plane.bytes[offset + 2];
        output.setPixelRgb(x, y, red, green, blue);
      }
    }

    return output;
  }

  void _buildReport() {
    _reportController.text = [
      '[몰래카메라 의심 신고 보조 문안]',
      '1. 발견 시각: ${_timeController.text.isEmpty ? "(미입력)" : _timeController.text}',
      '2. 장소: ${_placeController.text.isEmpty ? "(미입력)" : _placeController.text}',
      '3. 의심 정황:',
      _descController.text.isEmpty ? '(미입력)' : _descController.text,
      '4. 참고 안내:',
      '- AI 분석은 의심 지점을 참고용으로 제시합니다.',
      '- 현장에서는 실시간 스캔 탭에서 렌즈 반사를 직접 확인하세요.',
    ].join('\n');
  }

  Future<void> _saveReport() async {
    if (_reportController.text.trim().isEmpty) {
      _showMessage('먼저 신고 문안을 생성해주세요.');
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    await File('${dir.path}/safelens_report.txt')
        .writeAsString(_reportController.text);
    _showMessage('safelens_report.txt 파일로 저장했습니다.');
  }

  Future<void> _call112() async {
    final uri = Uri.parse('tel:112');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _sendSmsReport() async {
    final reportText = _reportController.text.trim();
    if (reportText.isEmpty) {
      _showMessage('먼저 문안 생성 버튼으로 신고 내용을 준비해주세요.');
      return;
    }

    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('문자 신고 확인'),
          content: const Text(
            '작성한 내용으로 112 문자 신고를 진행합니다.\n\n'
            '허위 신고 또는 장난 신고는 처벌 대상이 될 수 있습니다.\n'
            '내용이 사실에 기반한 신고인지 다시 확인해주세요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('확인 후 진행'),
            ),
          ],
        );
      },
    );

    if (approved != true) return;

    final uri = Uri(
      scheme: 'sms',
      path: '112',
      queryParameters: {'body': reportText},
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showMessage('문자 앱을 열 수 없습니다. 기기 설정을 확인해주세요.');
    }
  }

  void _openHelpPage() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _HelpPage()),
    );
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Palette.bg,
      body: Container(
        color: _Palette.bg,
        child: SafeArea(
          child: Column(
            children: [
              const _TopHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: _tab == 0
                        ? _homeTab()
                        : _tab == 1
                            ? _analysisTab()
                            : _tab == 2
                                ? _scanTab()
                                : _reportTab(),
                  ),
                ),
              ),
              _BottomTabs(
                  selected: _tab,
                  onChanged: (value) => setState(() => _tab = value)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _homeTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 64,
              height: 64,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _Palette.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _Palette.line),
              ),
              child: Image.asset('public/app-icon.png'),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SafeLens',
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: _Palette.text),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '현장 확인과 신고 준비를 한 화면 흐름으로 정리합니다.',
                    style: TextStyle(
                        fontSize: 15, color: _Palette.subText, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _HomeLinkCard(
          icon: Icons.search,
          title: '사진 분석',
          status: _boxes.isEmpty ? '탐지 전' : '탐지 ${_boxes.length}건',
          onTap: () => setState(() => _tab = 1),
          highlighted: true,
        ),
        const SizedBox(height: 12),
        _HomeLinkCard(
          icon: Icons.radio_button_checked,
          title: '실시간 스캔',
          status: _cameraOn ? (_torchOn ? '플래시 켜짐' : '준비됨') : '탐지 전',
          onTap: () => setState(() => _tab = 2),
        ),
        const SizedBox(height: 12),
        _HomeLinkCard(
          icon: Icons.priority_high,
          title: '신고 보조',
          status: _reportController.text.trim().isEmpty ? '문안 생성' : '문안 준비됨',
          onTap: () => setState(() => _tab = 3),
        ),
        const SizedBox(height: 12),
        _HomeLinkCard(
          icon: Icons.volunteer_activism_outlined,
          title: '도움 받기',
          status: '대처 안내',
          onTap: _openHelpPage,
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _Palette.primarySoft,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _Palette.line),
          ),
          child: const Text(
            '앱 결과는 확정 판정이 아니라 신고와 현장 확인을 돕는 참고 정보입니다.',
            style:
                TextStyle(color: _Palette.subText, fontSize: 16, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _analysisTab() {
    return _Panel(
      title: '의심 장소 분석',
      status: _boxes.isEmpty ? '탐지 전' : '탐지 ${_boxes.length}건',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: '사진 선택',
                  filled: true,
                  onTap: _pickImage,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  label: '초기화',
                  onTap: _analysisImage == null
                      ? null
                      : () => setState(() => _boxes = []),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: '분석',
                  compact: true,
                  filled: true,
                  onTap: _analysisImage == null ? null : _analyzeImage,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ImagePreview(image: _previewImage, boxes: _boxes),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _boxes.isEmpty
                  ? '사진을 선택한 뒤 분석을 실행하세요.'
                  : '의심 후보 ${_boxes.length}개를 표시했습니다.',
              style: const TextStyle(color: _Palette.subText, fontSize: 16),
            ),
          ),
          const SizedBox(height: 10),
          _DetectionResultList(boxes: _boxes),
        ],
      ),
    );
  }

  Widget _scanTab() {
    final controller = _cameraController;
    return _Panel(
      title: '실시간 반사 확인',
      status: _cameraOn ? (_torchOn ? '플래시 켜짐' : '카메라 켜짐') : '대기 중',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '플래시 반사 후보를 실시간으로 표시합니다. 표시된 지점은 확정 판정이 아니라 확인용 참고 정보입니다.',
            style: TextStyle(color: _Palette.subText, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                    label: '시작',
                    filled: true,
                    onTap: _cameraOn ? null : _startCamera),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                    label: '중지', onTap: _cameraOn ? _stopCamera : null),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  label: _flashDiffEnabled
                      ? (_torchOn ? 'ON 프레임' : 'OFF 프레임')
                      : '플래시 미지원',
                  filled: _torchOn,
                  onTap: null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: controller?.value.aspectRatio ?? 4 / 3,
            child: _PreviewFrame(
              child: controller == null || !controller.value.isInitialized
                  ? const Center(child: Text('카메라 시작 후 이곳에서 반사 확인'))
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(controller),
                        CustomPaint(
                            painter: BoxPainter(_liveBoxes, _liveSourceSize)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _cameraOn
                ? (_liveBoxes.isEmpty
                    ? '현재 표시할 의심 후보가 없습니다.'
                    : '자동 플래시 차분 · 현재 후보 ${_liveBoxes.length}개 · 반복 확인된 위치만 표시합니다.')
                : '카메라를 시작하면 실시간 후보가 화면에 표시됩니다.',
            style: const TextStyle(color: _Palette.subText, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _reportTab() {
    return _Panel(
      title: '신고 보조',
      status: '문안 생성',
      child: Column(
        children: [
          _TimeSelector(
            selectedHour: _selectedHour,
            selectedMinute: _selectedMinute,
            onHourChanged: _onHourChanged,
            onMinuteChanged: _selectedHour == 24 ? null : _onMinuteChanged,
          ),
          _Field(controller: _placeController, hint: '현재 위치 또는 장소'),
          _Field(controller: _descController, hint: '의심 정황', lines: 4),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                    label: '문안 생성', filled: true, onTap: _buildReport),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(label: '저장', onTap: _saveReport),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ActionButton(label: '문자 신고', onTap: _sendSmsReport),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _Palette.danger,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _call112,
                    child: const Text('112',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '문안 생성 후 문자 신고 또는 112 전화 신고를 선택할 수 있습니다.',
              style: TextStyle(color: _Palette.subText, fontSize: 14),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: _ActionButton(label: '피해 대처 안내 보기', onTap: _openHelpPage),
          ),
          const SizedBox(height: 10),
          _Field(
              controller: _reportController,
              hint: '신고 문안',
              lines: 10,
              readOnly: true),
        ],
      ),
    );
  }
}

class _TopHeader extends StatelessWidget {
  const _TopHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: _Palette.surface,
        border: Border(bottom: BorderSide(color: _Palette.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _Palette.surfaceMuted,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Image.asset('public/app-icon.png'),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SafeLens',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: _Palette.text)),
                SizedBox(height: 2),
                Text('의심 위치 확인 보조',
                    style: TextStyle(fontSize: 13, color: _Palette.subText)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _Palette.primarySoft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Local',
              style: TextStyle(
                  fontSize: 13,
                  color: _Palette.primary,
                  fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpPage extends StatelessWidget {
  const _HelpPage();

  static const _d4uUrl = 'https://d4u.stop.or.kr/main';
  static const _regionUrl = 'https://d4u.stop.or.kr/about/region/info';

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      await launchUrl(uri);
    }
  }

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Palette.bg,
      body: Container(
        color: _Palette.bg,
        child: SafeArea(
          child: Column(
            children: [
              const _TopHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: _Panel(
                      title: '도움 받기',
                      status: '대처 안내',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '불안하거나 피해가 의심될 때 바로 확인할 수 있는 대응 순서입니다.',
                            style: TextStyle(
                                color: _Palette.subText,
                                fontSize: 16,
                                height: 1.4),
                          ),
                          const SizedBox(height: 12),
                          _HelpSection(
                            icon: Icons.emergency_outlined,
                            title: '지금 바로 할 일',
                            items: const [
                              '긴급하거나 위험하면 즉시 112로 신고합니다.',
                              '가능하면 안전한 장소로 이동하고 주변에 도움을 요청합니다.',
                              '가해자와 직접 대면하거나 혼자 삭제를 요구하지 않습니다.',
                            ],
                            actions: [
                              _HelpAction(
                                  label: '112 전화',
                                  onTap: () => _call('112'),
                                  danger: true),
                              _HelpAction(
                                  label: '1366 전화', onTap: () => _call('1366')),
                            ],
                          ),
                          _HelpSection(
                            icon: Icons.inventory_2_outlined,
                            title: '증거 보존',
                            items: const [
                              '게시물 URL, 계정명, 업로드 시각, 캡처 화면을 보관합니다.',
                              '가능하면 원본 파일과 화면 녹화도 따로 보관합니다.',
                              '신고나 삭제 요청 전 증거가 사라지지 않도록 먼저 정리합니다.',
                              '불법촬영물을 불필요하게 재전송하거나 공유하지 않습니다.',
                            ],
                          ),
                          _HelpSection(
                            icon: Icons.account_balance_outlined,
                            title: '공공 지원',
                            items: const [
                              '중앙디지털성범죄피해자지원센터에서 상담, 삭제지원, 모니터링, 수사·법률·의료 연계를 받을 수 있습니다.',
                              '여성긴급전화 1366은 365일 24시간 초기 상담을 지원합니다.',
                              '지역 디지털성범죄피해자지원센터도 상담과 삭제 연계를 제공합니다.',
                            ],
                            actions: [
                              _HelpAction(
                                  label: '센터 열기',
                                  onTap: () => _openUrl(_d4uUrl)),
                              _HelpAction(
                                  label: '지역 센터',
                                  onTap: () => _openUrl(_regionUrl)),
                            ],
                          ),
                          _HelpSection(
                            icon: Icons.cleaning_services_outlined,
                            title: '삭제 지원',
                            items: const [
                              '우선 공공기관의 삭제지원과 모니터링을 확인합니다.',
                              '민간 삭제 대행 서비스는 비용, 환불 조건, 삭제 가능 범위, 개인정보 제공 범위를 확인해야 합니다.',
                              '앱에서는 이런 서비스를 디지털 장의사 또는 온라인 게시물 삭제 대행으로 안내할 수 있습니다.',
                            ],
                          ),
                          _HelpSection(
                            icon: Icons.favorite_border,
                            title: '법률·심리 지원',
                            items: const [
                              '수사 진행, 법률 상담, 의료 지원, 심리 상담을 함께 요청할 수 있습니다.',
                              '혼자 판단하기 어렵다면 상담기관을 통해 필요한 기관으로 연계받는 방식이 안전합니다.',
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomTabs extends StatelessWidget {
  const _BottomTabs({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = <({IconData icon, String label})>[
      (icon: Icons.home_outlined, label: '홈'),
      (icon: Icons.search, label: '분석'),
      (icon: Icons.radio_button_checked, label: '스캔'),
      (icon: Icons.priority_high, label: '신고'),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      decoration: const BoxDecoration(
        color: _Palette.surface,
        border: Border(top: BorderSide(color: _Palette.line)),
      ),
      child: Row(
        children: List.generate(items.length, (index) {
          final item = items[index];
          final active = selected == index;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onChanged(index),
                child: Ink(
                  height: 62,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: active ? _Palette.primarySoft : Colors.transparent,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(item.icon,
                          size: 24,
                          color: active ? _Palette.primary : _Palette.subText),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: active ? _Palette.primary : _Palette.subText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _HomeLinkCard extends StatelessWidget {
  const _HomeLinkCard({
    required this.icon,
    required this.title,
    required this.status,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String status;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _Palette.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: highlighted ? _Palette.primary : _Palette.line,
              width: highlighted ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: highlighted ? _Palette.primary : _Palette.surfaceMuted,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon,
                    size: 26,
                    color: highlighted ? Colors.white : _Palette.text),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _Palette.text),
                ),
              ),
              Text(
                status,
                style: TextStyle(
                  fontSize: 14,
                  color: highlighted ? _Palette.primary : _Palette.subText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right,
                  size: 22, color: _Palette.subText),
            ],
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel(
      {required this.title, required this.status, required this.child});

  final String title;
  final String status;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _Palette.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _Palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: _Palette.text),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _Palette.surfaceMuted,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status,
                  style: const TextStyle(
                      fontSize: 13,
                      color: _Palette.subText,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({
    required this.icon,
    required this.title,
    required this.items,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final List<String> items;
  final List<_HelpAction> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _Palette.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _Palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _Palette.primarySoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: _Palette.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _Palette.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: SizedBox(
                      width: 5,
                      height: 5,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: _Palette.subText, shape: BoxShape.circle),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                          fontSize: 14, color: _Palette.subText, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

class _HelpAction extends StatelessWidget {
  const _HelpAction({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: danger ? _Palette.danger : _Palette.text,
        side: BorderSide(color: danger ? _Palette.danger : _Palette.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.filled = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 46 : 50,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: filled ? _Palette.primary : _Palette.surface,
          foregroundColor: filled ? Colors.white : _Palette.text,
          disabledBackgroundColor: _Palette.surfaceMuted,
          disabledForegroundColor: const Color(0xffa2aab8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: filled ? _Palette.primary : _Palette.line),
          ),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        onPressed: onTap,
        child: Text(label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _TimeSelector extends StatelessWidget {
  const _TimeSelector({
    required this.selectedHour,
    required this.selectedMinute,
    required this.onHourChanged,
    required this.onMinuteChanged,
  });

  final int selectedHour;
  final int selectedMinute;
  final ValueChanged<int?> onHourChanged;
  final ValueChanged<int?>? onMinuteChanged;

  @override
  Widget build(BuildContext context) {
    final hours = List<int>.generate(25, (index) => index);
    final minutes = List<int>.generate(12, (index) => index * 5);
    final minuteDisabled = onMinuteChanged == null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _Palette.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _Palette.line),
        ),
        child: Row(
          children: [
            const Text('발견 시각',
                style: TextStyle(
                    fontSize: 15,
                    color: _Palette.subText,
                    fontWeight: FontWeight.w700)),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: selectedHour,
                decoration: _timeInputDecoration('시'),
                items: hours
                    .map((hour) => DropdownMenuItem<int>(
                          value: hour,
                          child: Text(hour.toString().padLeft(2, '0')),
                        ))
                    .toList(),
                onChanged: onHourChanged,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: minuteDisabled ? 0 : selectedMinute,
                decoration: _timeInputDecoration('분'),
                items: minutes
                    .map((minute) => DropdownMenuItem<int>(
                          value: minute,
                          child: Text(minute.toString().padLeft(2, '0')),
                        ))
                    .toList(),
                onChanged: onMinuteChanged,
              ),
            ),
            if (minuteDisabled) ...[
              const SizedBox(width: 8),
              const Text('(24시는 00분만)',
                  style: TextStyle(fontSize: 12, color: _Palette.subText)),
            ],
          ],
        ),
      ),
    );
  }

  InputDecoration _timeInputDecoration(String suffixText) {
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      suffixText: suffixText,
      filled: true,
      fillColor: Colors.white,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _Palette.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _Palette.primary, width: 1.4),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(
      {required this.controller,
      required this.hint,
      this.lines = 1,
      this.readOnly = false});

  final TextEditingController controller;
  final String hint;
  final int lines;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        minLines: lines,
        maxLines: lines,
        readOnly: readOnly,
        style: const TextStyle(fontSize: 16, color: _Palette.text),
        decoration: InputDecoration(
          filled: true,
          fillColor: readOnly ? _Palette.surfaceMuted : _Palette.surface,
          hintText: hint,
          hintStyle: const TextStyle(color: _Palette.subText),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _Palette.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _Palette.primary, width: 1.4),
          ),
        ),
      ),
    );
  }
}

class _DetectionResultList extends StatelessWidget {
  const _DetectionResultList({required this.boxes});

  final List<SuspiciousBox> boxes;

  @override
  Widget build(BuildContext context) {
    if (boxes.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _Palette.surfaceMuted,
          border: Border.all(color: _Palette.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          '분석 결과가 여기에 표시됩니다.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _Palette.subText, fontSize: 16),
        ),
      );
    }

    return Column(
      children: boxes
          .asMap()
          .entries
          .map(
            (entry) => Padding(
              padding: EdgeInsets.only(
                  bottom: entry.key == boxes.length - 1 ? 0 : 10),
              child:
                  _DetectionResultCard(index: entry.key + 1, box: entry.value),
            ),
          )
          .toList(),
    );
  }
}

class _DetectionResultCard extends StatelessWidget {
  const _DetectionResultCard({required this.index, required this.box});

  final int index;
  final SuspiciousBox box;

  @override
  Widget build(BuildContext context) {
    final color = _riskColor(box.risk);
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _Palette.surface,
        border: Border.all(color: _Palette.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: ColoredBox(
              color: color,
              child: const SizedBox(width: 6),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#$index ${box.type}',
                        style: const TextStyle(
                          color: _Palette.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        box.reason,
                        style: const TextStyle(
                          color: _Palette.subText,
                          fontSize: 15,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      box.risk,
                      style: const TextStyle(
                        color: _Palette.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${box.confidence}%',
                      style: const TextStyle(
                        color: _Palette.subText,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _Palette.surfaceMuted,
        border: Border.all(color: _Palette.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: child),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.image, required this.boxes});

  final ui.Image? image;
  final List<SuspiciousBox> boxes;

  @override
  Widget build(BuildContext context) {
    final current = image;
    return _PreviewFrame(
      child: AspectRatio(
        aspectRatio: current == null ? 4 / 3 : current.width / current.height,
        child: current == null
            ? const Center(
                child: Text('선택한 이미지가 여기에 표시됩니다.',
                    style: TextStyle(color: _Palette.subText)),
              )
            : CustomPaint(painter: ImageBoxPainter(current, boxes)),
      ),
    );
  }
}

class ImageBoxPainter extends CustomPainter {
  const ImageBoxPainter(this.image, this.boxes);

  final ui.Image image;
  final List<SuspiciousBox> boxes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint(),
    );
    BoxPainter(boxes, Size(image.width.toDouble(), image.height.toDouble()))
        .paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant ImageBoxPainter oldDelegate) =>
      image != oldDelegate.image || boxes != oldDelegate.boxes;
}

class BoxPainter extends CustomPainter {
  const BoxPainter(this.boxes, this.sourceSize);

  final List<SuspiciousBox> boxes;
  final Size? sourceSize;

  @override
  void paint(Canvas canvas, Size size) {
    final source = sourceSize;
    if (source == null || source.width == 0 || source.height == 0) return;

    final sx = size.width / source.width;
    final sy = size.height / source.height;

    for (var i = 0; i < boxes.length; i += 1) {
      final box = boxes[i];
      final color = _riskColor(box.risk);
      final stroke = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      final labelBg = Paint()..color = color;
      final rect =
          Rect.fromLTWH(box.x * sx, box.y * sy, box.w * sx, box.h * sy);
      canvas.drawRect(rect, stroke);

      final textPainter = TextPainter(
        text: TextSpan(
          text: '${i + 1} ${box.risk}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final top = math.max(0.0, rect.top - 20);
      canvas.drawRect(
          Rect.fromLTWH(rect.left, top, textPainter.width + 10, 20), labelBg);
      textPainter.paint(canvas, Offset(rect.left + 5, top + 3));
    }
  }

  @override
  bool shouldRepaint(covariant BoxPainter oldDelegate) =>
      boxes != oldDelegate.boxes || sourceSize != oldDelegate.sourceSize;
}
