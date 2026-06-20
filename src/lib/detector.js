function clamp01(value) {
  return Math.max(0, Math.min(1, value));
}

function riskFromScore(score) {
  if (score >= 0.78) return "높음";
  if (score >= 0.62) return "주의";
  return "낮음";
}

function colorSaturation(r, g, b) {
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  if (max === 0) return 0;
  return (max - min) / max;
}

function aspectScore(w, h) {
  const aspect = w > h ? w / Math.max(1, h) : h / Math.max(1, w);
  return clamp01((2.1 - aspect) / 1.1);
}

function fillScore(fill) {
  if (fill < 0.12) return 0;
  if (fill > 0.92) return 0.75;
  return clamp01((fill - 0.12) / 0.48);
}

function riskCandidate(score, confidenceBoost = 0) {
  const finalScore = clamp01(score + confidenceBoost);
  return {
    score: finalScore,
    confidence: Math.round(finalScore * 100),
    risk: riskFromScore(finalScore)
  };
}

export function detectSuspiciousSpots(ctx2d, w, h, options = {}) {
  const maxResults = options.maxResults ?? 8;
  const minConfidence = options.minConfidence ?? 0;
  const liveMode = Boolean(options.liveMode);
  const sensitivity = options.sensitivity || "normal";
  const previousImage = options.previousImageData || null;
  const config = {
    low: { local: 30, darkDelta: 34, brightDelta: 42, minScore: 0.66, fallbackScore: 0.6, maxOut: 3 },
    normal: { local: 26, darkDelta: 24, brightDelta: 30, minScore: 0.58, fallbackScore: 0.52, maxOut: 4 },
    high: { local: 22, darkDelta: 16, brightDelta: 22, minScore: 0.5, fallbackScore: 0.44, maxOut: 5 }
  }[sensitivity];

  const threshold = liveMode
    ? {
        ...config,
        local: Math.max(16, config.local - 4),
        darkDelta: Math.max(12, config.darkDelta - 6),
        brightDelta: Math.max(16, config.brightDelta - 8),
        minScore: config.minScore - 0.04,
        fallbackScore: config.fallbackScore - 0.04
      }
    : config;

  const image = options.imageData || ctx2d.getImageData(0, 0, w, h);
  const px = image.data;
  const previousPx =
    previousImage && previousImage.width === w && previousImage.height === h && previousImage.data?.length === px.length
      ? previousImage.data
      : null;
  const total = w * h;
  const lum = new Float32Array(total);
  const sat = new Float32Array(total);
  const positiveDiff = previousPx ? new Float32Array(total) : null;
  let globalDeltaSum = 0;

  for (let i = 0; i < total; i += 1) {
    const r = px[i * 4];
    const g = px[i * 4 + 1];
    const b = px[i * 4 + 2];
    lum[i] = r * 0.299 + g * 0.587 + b * 0.114;
    sat[i] = colorSaturation(r, g, b);
    if (positiveDiff) {
      const prev = previousPx[i * 4] * 0.299 + previousPx[i * 4 + 1] * 0.587 + previousPx[i * 4 + 2] * 0.114;
      const delta = lum[i] - prev;
      positiveDiff[i] = delta;
      globalDeltaSum += delta;
    }
  }

  if (positiveDiff) {
    const globalDelta = globalDeltaSum / Math.max(1, total);
    for (let i = 0; i < total; i += 1) {
      const normalized = positiveDiff[i] - globalDelta;
      positiveDiff[i] = normalized > 6 ? normalized : 0;
    }
  }

  const integral = new Float64Array((w + 1) * (h + 1));
  const integralSq = new Float64Array((w + 1) * (h + 1));
  for (let y = 0; y < h; y += 1) {
    let row = 0;
    let rowSq = 0;
    for (let x = 0; x < w; x += 1) {
      const value = lum[y * w + x];
      row += value;
      rowSq += value * value;
      const dst = (y + 1) * (w + 1) + x + 1;
      integral[dst] = integral[y * (w + 1) + x + 1] + row;
      integralSq[dst] = integralSq[y * (w + 1) + x + 1] + rowSq;
    }
  }

  const boxStats = (x0, y0, x1, y1) => {
    const ax = Math.max(0, Math.min(w - 1, Math.floor(x0)));
    const ay = Math.max(0, Math.min(h - 1, Math.floor(y0)));
    const bx = Math.max(0, Math.min(w - 1, Math.ceil(x1)));
    const by = Math.max(0, Math.min(h - 1, Math.ceil(y1)));
    const stride = w + 1;
    const area = Math.max(1, (bx - ax + 1) * (by - ay + 1));
    const sum = integral[(by + 1) * stride + bx + 1] - integral[ay * stride + bx + 1] - integral[(by + 1) * stride + ax] + integral[ay * stride + ax];
    const sumSq =
      integralSq[(by + 1) * stride + bx + 1] -
      integralSq[ay * stride + bx + 1] -
      integralSq[(by + 1) * stride + ax] +
      integralSq[ay * stride + ax];
    const mean = sum / area;
    return { mean, std: Math.sqrt(Math.max(0, sumSq / area - mean * mean)), area };
  };

  const localMean = (x, y, radius) => boxStats(x - radius, y - radius, x + radius, y + radius).mean;
  const darkMask = new Uint8Array(total);
  const brightMask = new Uint8Array(total);
  const glassMask = new Uint8Array(total);
  const localRadius = Math.max(14, Math.min(liveMode ? 26 : 48, Math.round(Math.min(w, h) * 0.04)));

  for (let i = 0; i < total; i += 1) {
    const x = i % w;
    const y = (i / w) | 0;
    const value = lum[i];
    const mean = localMean(x, y, localRadius);
    const darkDelta = mean - value;
    const brightDelta = value - mean;

    if (value <= 72 || (value <= 150 && darkDelta >= threshold.darkDelta)) darkMask[i] = 1;
    if (value >= 232 || (value >= 175 && brightDelta >= threshold.brightDelta && sat[i] < 0.62)) brightMask[i] = 1;
    if (value >= 115 && value <= 245 && Math.abs(brightDelta) >= threshold.brightDelta * 0.55 && sat[i] < 0.82) glassMask[i] = 1;
  }

  const walk = (start, mask, visited) => {
    const queue = [start];
    visited[start] = 1;
    let minX = w;
    let minY = h;
    let maxX = 0;
    let maxY = 0;
    let count = 0;
    let sum = 0;
    let satSum = 0;

    while (queue.length) {
      const cur = queue.pop();
      const x = cur % w;
      const y = (cur / w) | 0;
      minX = Math.min(minX, x);
      minY = Math.min(minY, y);
      maxX = Math.max(maxX, x);
      maxY = Math.max(maxY, y);
      count += 1;
      sum += lum[cur];
      satSum += sat[cur];

      const nexts = [cur - 1, cur + 1, cur - w, cur + w];
      for (const next of nexts) {
        if (next < 0 || next >= total) continue;
        if (Math.abs((next % w) - x) > 1) continue;
        if (!mask[next] || visited[next]) continue;
        visited[next] = 1;
        queue.push(next);
      }
    }

    const bw = maxX - minX + 1;
    const bh = maxY - minY + 1;
    return {
      x: minX,
      y: minY,
      w: bw,
      h: bh,
      x1: maxX,
      y1: maxY,
      cx: minX + bw / 2,
      cy: minY + bh / 2,
      count,
      area: bw * bh,
      fill: count / Math.max(1, bw * bh),
      mean: sum / Math.max(1, count),
      sat: satSum / Math.max(1, count)
    };
  };

  const collectSpots = (mask, kind) => {
    const visited = new Uint8Array(total);
    const spots = [];
    const maxSide = liveMode ? 86 : 132;
    const maxArea = liveMode ? 3200 : 7200;

    for (let i = 0; i < total; i += 1) {
      if (!mask[i] || visited[i]) continue;
      const spot = walk(i, mask, visited);
      if (spot.count < 3) continue;
      if (spot.w > maxSide || spot.h > maxSide || spot.area > maxArea) continue;
      if (spot.fill < 0.08) continue;
      const shape = aspectScore(spot.w, spot.h) * 0.72 + fillScore(spot.fill) * 0.28;
      if (shape < 0.24) continue;
      spots.push({ ...spot, kind, shape });
    }

    return spots;
  };

  const rawSpots = [
    ...collectSpots(darkMask, "dark"),
    ...collectSpots(brightMask, "bright"),
    ...collectSpots(glassMask, "glass")
  ];

  const ringStats = (spot, pad = 8) => {
    const outer = boxStats(spot.x - pad, spot.y - pad, spot.x1 + pad, spot.y1 + pad);
    const inner = boxStats(spot.x, spot.y, spot.x1, spot.y1);
    const ringArea = Math.max(1, outer.area - inner.area);
    const ringMean = (outer.mean * outer.area - inner.mean * inner.area) / ringArea;
    return { mean: ringMean, std: outer.std };
  };

  const radialStats = (spot) => {
    const radius = Math.max(4, Math.min(liveMode ? 38 : 62, Math.max(spot.w, spot.h) / 2));
    let innerSum = 0;
    let innerCount = 0;
    let ringSum = 0;
    let ringCount = 0;
    let brightCount = 0;
    let coreBrightCount = 0;
    let outerBrightCount = 0;
    const outer = Math.ceil(radius * 1.85);

    for (let y = Math.max(0, Math.floor(spot.cy - outer)); y <= Math.min(h - 1, Math.ceil(spot.cy + outer)); y += 1) {
      for (let x = Math.max(0, Math.floor(spot.cx - outer)); x <= Math.min(w - 1, Math.ceil(spot.cx + outer)); x += 1) {
        const dist = Math.hypot(x - spot.cx, y - spot.cy);
        const value = lum[y * w + x];
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

    const coreBrightRatio = innerCount ? coreBrightCount / innerCount : 0;
    const outerBrightRatio = ringCount ? outerBrightCount / ringCount : 0;

    return {
      center: innerCount ? innerSum / innerCount : spot.mean,
      ring: ringCount ? ringSum / ringCount : spot.mean,
      contrast: Math.abs((ringCount ? ringSum / ringCount : spot.mean) - (innerCount ? innerSum / innerCount : spot.mean)),
      brightRatio: (innerCount + ringCount) ? brightCount / (innerCount + ringCount) : 0,
      compactHighlight: clamp01((coreBrightRatio - outerBrightRatio + 0.03) / 0.18)
    };
  };

  const flashDeltaStats = (spot) => {
    if (!positiveDiff) return { score: 0, mean: 0, peak: 0, hotRatio: 0 };
    const radius = Math.max(4, Math.min(liveMode ? 42 : 64, Math.max(spot.w, spot.h) * 0.85));
    let sum = 0;
    let count = 0;
    let hot = 0;
    let peak = 0;

    for (let y = Math.max(0, Math.floor(spot.cy - radius)); y <= Math.min(h - 1, Math.ceil(spot.cy + radius)); y += 1) {
      for (let x = Math.max(0, Math.floor(spot.cx - radius)); x <= Math.min(w - 1, Math.ceil(spot.cx + radius)); x += 1) {
        if (Math.hypot(x - spot.cx, y - spot.cy) > radius) continue;
        const delta = positiveDiff[y * w + x];
        sum += delta;
        count += 1;
        if (delta >= 24) hot += 1;
        peak = Math.max(peak, delta);
      }
    }

    const mean = count ? sum / count : 0;
    const hotRatio = count ? hot / count : 0;
    return {
      mean,
      peak,
      hotRatio,
      score: clamp01(mean / 28) * 0.45 + clamp01(peak / 70) * 0.35 + clamp01(hotRatio / 0.16) * 0.2
    };
  };

  const sampleLum = (x, y) => {
    const sx = Math.max(0, Math.min(w - 1, Math.round(x)));
    const sy = Math.max(0, Math.min(h - 1, Math.round(y)));
    return lum[sy * w + sx];
  };

  const radialSymmetryScore = (spot) => {
    const radius = Math.max(4, Math.min(liveMode ? 36 : 58, Math.max(spot.w, spot.h) * 0.58));
    const samples = [];
    const pairs = 12;
    for (let i = 0; i < pairs; i += 1) {
      const angle = (Math.PI * 2 * i) / pairs;
      const x = spot.cx + Math.cos(angle) * radius;
      const y = spot.cy + Math.sin(angle) * radius;
      samples.push(sampleLum(x, y));
    }

    const mean = samples.reduce((acc, value) => acc + value, 0) / samples.length;
    const variance = samples.reduce((acc, value) => acc + (value - mean) ** 2, 0) / samples.length;
    const std = Math.sqrt(variance);
    let pairDiff = 0;
    for (let i = 0; i < pairs / 2; i += 1) {
      pairDiff += Math.abs(samples[i] - samples[i + pairs / 2]);
    }
    const oppositeScore = clamp01(1 - pairDiff / (pairs * 24));
    const evennessScore = clamp01(1 - std / 46);
    return evennessScore * 0.58 + oppositeScore * 0.42;
  };

  const glarePenalty = (spot, radial) => {
    const diameter = Math.max(spot.w, spot.h);
    const largeBrightPatch = spot.kind !== "dark" && diameter > (liveMode ? 34 : 48) && spot.fill > 0.58;
    const broadHighlight = radial.brightRatio > 0.34;
    return (largeBrightPatch ? 0.18 : 0) + (broadHighlight ? 0.14 : 0);
  };

  const linePenalty = (spot) => {
    const pad = 6;
    const x0 = Math.max(0, spot.x - pad);
    const y0 = Math.max(0, spot.y - pad);
    const x1 = Math.min(w - 1, spot.x1 + pad);
    const y1 = Math.min(h - 1, spot.y1 + pad);
    let strongRows = 0;
    let strongCols = 0;

    for (let y = y0; y <= y1; y += 1) {
      let hits = 0;
      for (let x = x0; x <= x1; x += 1) if (lum[y * w + x] < 88 || lum[y * w + x] > 220) hits += 1;
      if (hits / Math.max(1, x1 - x0 + 1) > 0.72) strongRows += 1;
    }

    for (let x = x0; x <= x1; x += 1) {
      let hits = 0;
      for (let y = y0; y <= y1; y += 1) if (lum[y * w + x] < 88 || lum[y * w + x] > 220) hits += 1;
      if (hits / Math.max(1, y1 - y0 + 1) > 0.72) strongCols += 1;
    }

    return clamp01((Math.max(strongRows, strongCols) - 1) / 5);
  };

  const repeatedPenalty = (spot) => {
    const similar = rawSpots.filter((other) => {
      if (other === spot || other.kind !== spot.kind) return false;
      const dist = Math.hypot(spot.cx - other.cx, spot.cy - other.cy);
      if (dist > 120) return false;
      const sizeRatio = Math.max(spot.area, other.area) / Math.max(1, Math.min(spot.area, other.area));
      return sizeRatio < 2.4;
    }).length;
    return clamp01(similar / 5);
  };

  const edgePenalty = (spot) => {
    const margin = Math.min(spot.x, spot.y, w - 1 - spot.x1, h - 1 - spot.y1);
    return margin >= 8 ? 0 : (8 - margin) / 24;
  };

  const nearestEvidence = (spot, kinds) => {
    let best = 0;
    for (const other of rawSpots) {
      if (other === spot || !kinds.includes(other.kind)) continue;
      const dist = Math.hypot(spot.cx - other.cx, spot.cy - other.cy);
      const radius = Math.max(22, Math.min(liveMode ? 70 : 110, Math.max(spot.w, spot.h, other.w, other.h) * 2.2 + 18));
      if (dist > radius) continue;
      const sizeRatio = Math.max(spot.area, other.area) / Math.max(1, Math.min(spot.area, other.area));
      if (sizeRatio > 10) continue;
      best = Math.max(best, clamp01(1 - dist / radius) * 0.65 + other.shape * 0.25 + clamp01(other.count / 120) * 0.1);
    }
    return best;
  };

  const verifyLensCandidate = (spot) => {
    const ring = ringStats(spot, Math.max(6, Math.min(18, Math.round(Math.max(spot.w, spot.h) * 0.35))));
    const radial = radialStats(spot);
    const flashDelta = flashDeltaStats(spot);
    const symmetryScore = radialSymmetryScore(spot);
    const localContrast = Math.abs(spot.mean - ring.mean);
    const diameter = Math.max(spot.w, spot.h);
    const minDiameter = liveMode ? 3 : 4;
    const maxDiameter = liveMode ? 86 : 132;
    const sizeScore = clamp01((diameter - minDiameter) / 18) * clamp01((maxDiameter - diameter) / maxDiameter + 0.5);
    const contrastScore = clamp01(Math.max(localContrast, radial.contrast) / 65);
    const highlightScore = spot.kind === "bright" || spot.kind === "glass" ? clamp01((spot.mean - ring.mean + 22) / 95) : radial.brightRatio > 0.018 ? 0.28 : 0;
    const darkCoreScore = spot.kind === "dark" ? clamp01((ring.mean - spot.mean + 18) / 85) : nearestEvidence(spot, ["dark"]) * 0.42;
    const companionScore =
      spot.kind === "dark" ? nearestEvidence(spot, ["bright", "glass"]) : nearestEvidence(spot, ["dark", "bright", "glass"]);
    const retroReflectionScore = Math.max(radial.compactHighlight, flashDelta.score);
    const artifactPenalty =
      linePenalty(spot) * 0.24 +
      repeatedPenalty(spot) * 0.26 +
      edgePenalty(spot) * 0.22 +
      glarePenalty(spot, radial) +
      clamp01(ring.std / 150) * 0.06;

    const evidenceFlags = [
      spot.shape >= 0.54,
      symmetryScore >= 0.5,
      contrastScore >= 0.38,
      retroReflectionScore >= 0.34,
      darkCoreScore >= 0.28,
      companionScore >= 0.26
    ];
    const evidenceCount = evidenceFlags.filter(Boolean).length;
    const strongOpticalEvidence =
      (retroReflectionScore >= 0.62 && spot.shape >= 0.48) ||
      (darkCoreScore >= 0.52 && contrastScore >= 0.42) ||
      (companionScore >= 0.46 && contrastScore >= 0.38);
    const requiredEvidence = sensitivity === "high" ? 2 : 3;
    const crossCheckPenalty = evidenceCount >= requiredEvidence || strongOpticalEvidence ? 0 : 0.16 + (requiredEvidence - evidenceCount) * 0.08;

    const score =
      0.14 +
      spot.shape * 0.18 +
      symmetryScore * 0.1 +
      sizeScore * 0.12 +
      contrastScore * 0.16 +
      highlightScore * 0.12 +
      darkCoreScore * 0.12 +
      companionScore * 0.1 +
      retroReflectionScore * 0.12 -
      artifactPenalty -
      crossCheckPenalty;

    let type = "렌즈 후보";
    let reason = "원형 형태와 주변 대비가 렌즈 패턴과 유사함";
    if (spot.kind === "dark") {
      type = companionScore > 0.22 ? "렌즈 코어 의심" : "어두운 렌즈 후보";
      reason = companionScore > 0.22 ? "어두운 코어와 가까운 반사/유리면 후보가 함께 확인됨" : "주변보다 어두운 원형 렌즈 후보";
    } else if (spot.kind === "bright") {
      type = "렌즈 반사 의심";
      reason = flashDelta.score > 0.28 ? "프레임 간 밝기 증분이 큰 원형 반사 후보" : "강한 반사와 원형 렌즈 표면 후보";
    } else if (spot.kind === "glass") {
      type = "렌즈 표면 의심";
      reason = "빛을 받은 유리면/코팅 반사 후보";
    }

    return {
      ...spot,
      ...riskCandidate(score),
      type,
      reason,
      evidence: {
        shape: Math.round(spot.shape * 100),
        symmetry: Math.round(symmetryScore * 100),
        contrast: Math.round(contrastScore * 100),
        retroReflection: Math.round(retroReflectionScore * 100),
        darkCore: Math.round(darkCoreScore * 100),
        companion: Math.round(companionScore * 100),
        crossChecks: evidenceCount
      },
      crossChecks: evidenceCount
    };
  };

  const verified = rawSpots
    .map(verifyLensCandidate)
    .filter((spot) => spot.score >= threshold.fallbackScore && (spot.crossChecks >= (sensitivity === "high" ? 2 : 3) || spot.evidence.retroReflection >= 62))
    .sort((a, b) => b.score - a.score);

  const merged = [];
  verified.forEach((spot) => {
    const duplicate = merged.find((prev) => Math.hypot(prev.cx - spot.cx, prev.cy - spot.cy) < Math.max(14, Math.min(prev.w, spot.w) * 0.55));
    if (!duplicate) {
      merged.push(spot);
    } else if (spot.score > duplicate.score) {
      Object.assign(duplicate, spot);
    }
  });

  const strong = merged.filter((spot) => spot.score >= threshold.minScore);
  const fallback = strong.length ? strong : merged.slice(0, Math.min(2, threshold.maxOut));

  return fallback
    .filter((item) => item.confidence >= minConfidence)
    .sort((a, b) => b.score - a.score)
    .slice(0, Math.min(maxResults, threshold.maxOut));
}
