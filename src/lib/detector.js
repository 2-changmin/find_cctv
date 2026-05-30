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

export function detectSuspiciousSpots(ctx2d, w, h, options = {}) {
  const maxResults = options.maxResults ?? 8;
  const data = ctx2d.getImageData(0, 0, w, h);
  const px = data.data;
  const bright = new Uint8Array(w * h);
  const dark = new Uint8Array(w * h);
  const visitedBright = new Uint8Array(w * h);
  const visitedDark = new Uint8Array(w * h);
  const lum = new Float32Array(w * h);
  const sat = new Float32Array(w * h);

  const sensitivity = options.sensitivity || "normal";
  const thresholdConfig = {
    low: { bright: 248, dark: 34, sat: 0.30, ringContrast: 0.85, minArea: 35 },
    normal: { bright: 244, dark: 38, sat: 0.28, ringContrast: 0.92, minArea: 28 },
    high: { bright: 240, dark: 42, sat: 0.26, ringContrast: 0.98, minArea: 18 }
  }[sensitivity];

  const BRIGHT_TH = thresholdConfig.bright;
  const DARK_TH = thresholdConfig.dark;
  const SAT_TH = thresholdConfig.sat;

  for (let i = 0; i < w * h; i += 1) {
    const r = px[i * 4];
    const g = px[i * 4 + 1];
    const b = px[i * 4 + 2];
    const v = r * 0.299 + g * 0.587 + b * 0.114;
    lum[i] = v;
    sat[i] = colorSaturation(r, g, b);
    if (v >= BRIGHT_TH && sat[i] < SAT_TH) bright[i] = 1;
    if (v <= DARK_TH) dark[i] = 1;
  }

  const candidates = [];
  const dirs = [-1, 1, -w, w];

  const ringStats = (x0, y0, x1, y1) => {
    let sum = 0;
    let sumSq = 0;
    let count = 0;
    for (let y = Math.max(0, y0 - 3); y <= Math.min(h - 1, y1 + 3); y += 1) {
      for (let x = Math.max(0, x0 - 3); x <= Math.min(w - 1, x1 + 3); x += 1) {
        if (x >= x0 && x <= x1 && y >= y0 && y <= y1) continue;
        const v = lum[y * w + x];
        sum += v;
        sumSq += v * v;
        count += 1;
      }
    }
    if (!count) return { mean: 0, std: 0 };
    const mean = sum / count;
    return { mean, std: Math.sqrt(Math.max(0, sumSq / count - mean * mean)) };
  };

  const edgePenalty = (x0, y0, x1, y1) => {
    const margin = Math.min(x0, y0, w - 1 - x1, h - 1 - y1);
    if (margin >= 10) return 0;
    return (10 - margin) / 30;
  };

  const circularityPenalty = (bw, bh) => {
    const aspect = bw > bh ? bw / Math.max(1, bh) : bh / Math.max(1, bw);
    return Math.max(0, aspect - 1.45) * 0.22;
  };

  const pushCandidate = (candidate) => {
    const duplicate = candidates.find((prev) => {
      const cx = candidate.x + candidate.w / 2;
      const cy = candidate.y + candidate.h / 2;
      const pxCenter = prev.x + prev.w / 2;
      const pyCenter = prev.y + prev.h / 2;
      return Math.abs(cx - pxCenter) < 12 && Math.abs(cy - pyCenter) < 12;
    });

    if (!duplicate) {
      candidates.push(candidate);
      return;
    }

    if (candidate.score > duplicate.score) Object.assign(duplicate, candidate);
  };

  const walk = (start, mask, visited) => {
    const queue = [start];
    visited[start] = 1;
    let minX = w;
    let minY = h;
    let maxX = 0;
    let maxY = 0;
    let count = 0;
    let sumL = 0;

    while (queue.length) {
      const cur = queue.pop();
      const x = cur % w;
      const y = (cur / w) | 0;
      minX = Math.min(minX, x);
      minY = Math.min(minY, y);
      maxX = Math.max(maxX, x);
      maxY = Math.max(maxY, y);
      count += 1;
      sumL += lum[cur];

      for (const d of dirs) {
        const next = cur + d;
        if (next < 0 || next >= w * h) continue;
        if (Math.abs((next % w) - x) > 1) continue;
        if (mask[next] && !visited[next]) {
          visited[next] = 1;
          queue.push(next);
        }
      }
    }

    return {
      x: minX,
      y: minY,
      w: maxX - minX + 1,
      h: maxY - minY + 1,
      count,
      mean: sumL / count
    };
  };

  for (let i = 0; i < w * h; i += 1) {
    if (!bright[i] || visitedBright[i]) continue;
    const spot = walk(i, bright, visitedBright);
    const area = spot.w * spot.h;
    const fill = spot.count / Math.max(1, area);
    const ring = ringStats(spot.x, spot.y, spot.x + spot.w - 1, spot.y + spot.h - 1);
    const contrast = spot.mean - ring.mean;

    if (spot.count >= 3 && spot.count <= 120 && area <= 180 && spot.w <= 18 && spot.h <= 18 && fill >= 0.32 && contrast > 30) {
      const score =
        0.48 +
        clamp01(contrast / 115) * 0.28 +
        clamp01(fill) * 0.12 -
        circularityPenalty(spot.w, spot.h) -
        edgePenalty(spot.x, spot.y, spot.x + spot.w - 1, spot.y + spot.h - 1) -
        clamp01(ring.std / 90) * 0.08;

      if (score >= 0.56) {
        pushCandidate({
          ...spot,
          type: "반사 후보",
          score: clamp01(score),
          confidence: Math.round(clamp01(score) * 100),
          risk: riskFromScore(score),
          reason: "작고 강한 무채색 반사점"
        });
      }
    }
  }

  for (let i = 0; i < w * h; i += 1) {
    if (!dark[i] || visitedDark[i]) continue;
    const spot = walk(i, dark, visitedDark);
    const area = spot.w * spot.h;
    const fill = spot.count / Math.max(1, area);
    const ring = ringStats(spot.x, spot.y, spot.x + spot.w - 1, spot.y + spot.h - 1);
    const contrast = ring.mean - spot.mean;

    if (spot.count >= 6 && spot.count <= 170 && area <= 260 && spot.w <= 24 && spot.h <= 24 && fill >= 0.38 && contrast > 34) {
      const score =
        0.46 +
        clamp01(contrast / 125) * 0.3 +
        clamp01(fill) * 0.12 -
        circularityPenalty(spot.w, spot.h) -
        edgePenalty(spot.x, spot.y, spot.x + spot.w - 1, spot.y + spot.h - 1);

      if (score >= 0.55) {
        pushCandidate({
          ...spot,
          type: "렌즈 코어 후보",
          score: clamp01(score),
          confidence: Math.round(clamp01(score) * 100),
          risk: riskFromScore(score),
          reason: "작고 어두운 원형 코어"
        });
      }
    }
  }

  return candidates.sort((a, b) => b.score - a.score).slice(0, maxResults);
}
