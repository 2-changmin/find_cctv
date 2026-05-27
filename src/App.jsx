import { useEffect, useRef, useState } from "react";

function detectSuspiciousSpots(ctx2d, w, h) {
  const data = ctx2d.getImageData(0, 0, w, h);
  const px = data.data;
  const bright = new Uint8Array(w * h);
  const dark = new Uint8Array(w * h);
  const visitedBright = new Uint8Array(w * h);
  const visitedDark = new Uint8Array(w * h);
  const lum = new Float32Array(w * h);

  // 1) 기본 후보: 매우 밝은 점 반사 / 매우 어두운 렌즈 코어
  const BRIGHT_TH = 242;
  const DARK_TH = 42;
  for (let i = 0; i < w * h; i += 1) {
    const v = (px[i * 4] + px[i * 4 + 1] + px[i * 4 + 2]) / 3;
    lum[i] = v;
    if (v >= BRIGHT_TH) bright[i] = 1;
    if (v <= DARK_TH) dark[i] = 1;
  }

  const boxes = new Map();
  const dirs = [-1, 1, -w, w];

  const getRingContrast = (x0, y0, x1, y1, objectMean) => {
    let ringSum = 0;
    let ringCount = 0;
    for (let y = Math.max(0, y0 - 2); y <= Math.min(h - 1, y1 + 2); y += 1) {
      for (let x = Math.max(0, x0 - 2); x <= Math.min(w - 1, x1 + 2); x += 1) {
        if (x >= x0 && x <= x1 && y >= y0 && y <= y1) continue;
        ringSum += lum[y * w + x];
        ringCount += 1;
      }
    }
    if (!ringCount) return 0;
    return objectMean - ringSum / ringCount;
  };

  const addCandidate = (x, y, bw, bh, score) => {
    const key = `${Math.round(x / 8)}-${Math.round(y / 8)}`;
    const prev = boxes.get(key);
    if (!prev || prev.score < score) boxes.set(key, { x, y, w: bw, h: bh, score });
  };

  const circularityPenalty = (bw, bh) => {
    const aspect = bw > bh ? bw / Math.max(1, bh) : bh / Math.max(1, bw);
    return Math.max(0, aspect - 1.8) * 0.25;
  };

  // 2) 밝은 반사 후보: 작고 대비가 강하고 거의 원형에 가까운 점
  for (let i = 0; i < w * h; i += 1) {
    if (!bright[i] || visitedBright[i]) continue;
    const queue = [i];
    visitedBright[i] = 1;
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
        if (bright[next] && !visitedBright[next]) {
          visitedBright[next] = 1;
          queue.push(next);
        }
      }
    }

    const bw = maxX - minX + 1;
    const bh = maxY - minY + 1;
    const area = bw * bh;
    const meanL = sumL / count;
    const contrast = getRingContrast(minX, minY, maxX, maxY, meanL);
    if (count >= 4 && area <= 220 && bw <= 22 && bh <= 22 && contrast > 20) {
      const score = 0.5 + Math.min(0.35, contrast / 110) - circularityPenalty(bw, bh);
      if (score >= 0.52) addCandidate(minX, minY, bw, bh, score);
    }
  }

  // 3) 어두운 렌즈 코어 후보: 작은 어두운 점 + 주변이 상대적으로 밝아야 함
  for (let i = 0; i < w * h; i += 1) {
    if (!dark[i] || visitedDark[i]) continue;
    const queue = [i];
    visitedDark[i] = 1;
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
        if (dark[next] && !visitedDark[next]) {
          visitedDark[next] = 1;
          queue.push(next);
        }
      }
    }

    const bw = maxX - minX + 1;
    const bh = maxY - minY + 1;
    const area = bw * bh;
    const meanL = sumL / count;
    const ringContrast = getRingContrast(minX, minY, maxX, maxY, meanL) * -1;
    if (count >= 8 && area <= 340 && bw <= 30 && bh <= 30 && ringContrast > 24) {
      const score = 0.47 + Math.min(0.35, ringContrast / 120) - circularityPenalty(bw, bh);
      if (score >= 0.5) addCandidate(minX, minY, bw, bh, score);
    }
  }

  // 4) 최종: 상위 후보만 제한 (과다 표기를 줄이기 위해 최대 8개)
  return Array.from(boxes.values()).sort((a, b) => b.score - a.score).slice(0, 8);
}

export default function App() {
  const previewCanvasRef = useRef(null);
  const videoRef = useRef(null);
  const overlayRef = useRef(null);
  const loadedImgRef = useRef(null);
  const streamRef = useRef(null);
  const videoTrackRef = useRef(null);
  const scanTickRef = useRef(null);

  const [tab, setTab] = useState("analyze");
  const [boxes, setBoxes] = useState([]);
  const [cameraOn, setCameraOn] = useState(false);
  const [flashEnabled, setFlashEnabled] = useState(false);
  const [torchOn, setTorchOn] = useState(false);
  const [hasImage, setHasImage] = useState(false);
  const [reportText, setReportText] = useState("");
  const [form, setForm] = useState({ reportTime: "", reportPlace: "", reportDesc: "" });

  const drawBaseImage = () => {
    const canvas = previewCanvasRef.current;
    const img = loadedImgRef.current;
    if (!canvas || !img) return null;
    const ctx = canvas.getContext("2d");
    const ratio = img.width / img.height;
    const targetW = Math.min(900, img.width);
    const targetH = Math.round(targetW / ratio);
    canvas.width = targetW;
    canvas.height = targetH;
    ctx.drawImage(img, 0, 0, targetW, targetH);
    return ctx;
  };

  const drawBoxes = (nextBoxes) => {
    const canvas = previewCanvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    ctx.lineWidth = 2;
    ctx.font = "12px sans-serif";
    nextBoxes.forEach((b, idx) => {
      const label = `의심 ${idx + 1}`;
      const tw = ctx.measureText(label).width + 8;
      ctx.strokeStyle = "#f43f5e";
      ctx.strokeRect(b.x, b.y, b.w, b.h);
      ctx.fillStyle = "#be123c";
      ctx.fillRect(b.x, Math.max(0, b.y - 16), tw, 16);
      ctx.fillStyle = "#fff";
      ctx.fillText(label, b.x + 4, Math.max(11, b.y - 4));
    });
  };

  const onFileChange = (event) => {
    const file = event.target.files?.[0];
    if (!file) return;
    const img = new Image();
    img.onload = () => {
      loadedImgRef.current = img;
      drawBaseImage();
      setBoxes([]);
      setHasImage(true);
    };
    img.src = URL.createObjectURL(file);
  };

  const analyzeImage = () => {
    const ctx = drawBaseImage();
    const canvas = previewCanvasRef.current;
    if (!ctx || !canvas) return;
    const nextBoxes = detectSuspiciousSpots(ctx, canvas.width, canvas.height);
    drawBoxes(nextBoxes);
    setBoxes(nextBoxes);
  };

  const startCamera = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" }, audio: false });
      videoRef.current.srcObject = stream;
      streamRef.current = stream;
      videoTrackRef.current = stream.getVideoTracks()[0] || null;
      setFlashEnabled(Boolean(videoTrackRef.current));
      setCameraOn(true);
    } catch {
      alert("카메라 접근 권한이 필요합니다.");
    }
  };

  const stopCamera = () => {
    if (scanTickRef.current) clearInterval(scanTickRef.current);
    scanTickRef.current = null;
    if (streamRef.current) streamRef.current.getTracks().forEach((track) => track.stop());
    streamRef.current = null;
    if (videoRef.current) videoRef.current.srcObject = null;
    if (overlayRef.current) {
      const octx = overlayRef.current.getContext("2d");
      octx.clearRect(0, 0, overlayRef.current.width, overlayRef.current.height);
    }
    setCameraOn(false);
    setFlashEnabled(false);
    setTorchOn(false);
  };

  const toggleFlash = async () => {
    const track = videoTrackRef.current;
    if (!track) return;
    try {
      const next = !torchOn;
      await track.applyConstraints({ advanced: [{ torch: next }] });
      setTorchOn(next);
    } catch {
      alert("이 기기는 플래시 제어를 지원하지 않습니다.");
    }
  };

  useEffect(() => {
    if (!cameraOn) return undefined;
    scanTickRef.current = setInterval(() => {
      if (!videoRef.current?.videoWidth || !overlayRef.current) return;
      const video = videoRef.current;
      const overlay = overlayRef.current;
      overlay.width = video.videoWidth;
      overlay.height = video.videoHeight;
      const octx = overlay.getContext("2d");
      octx.clearRect(0, 0, overlay.width, overlay.height);

      const temp = document.createElement("canvas");
      temp.width = overlay.width;
      temp.height = overlay.height;
      const tctx = temp.getContext("2d");
      tctx.drawImage(video, 0, 0, temp.width, temp.height);
      const liveBoxes = detectSuspiciousSpots(tctx, temp.width, temp.height).slice(0, 8);

      octx.strokeStyle = "#facc15";
      octx.lineWidth = 2;
      liveBoxes.forEach((b) => octx.strokeRect(b.x, b.y, b.w, b.h));
    }, 500);

    return () => scanTickRef.current && clearInterval(scanTickRef.current);
  }, [cameraOn]);

  useEffect(() => () => stopCamera(), []);

  const buildReport = () => {
    setReportText([
      "[몰래카메라 의심 신고 보조 문안]",
      `1. 발견 일시: ${form.reportTime || "(미입력)"}`,
      `2. 장소: ${form.reportPlace || "(미입력)"}`,
      "3. 의심 정황:",
      form.reportDesc || "(미입력)",
      "4. 앱 분석 안내:",
      "- AI 분석은 의심 지점을 제시했으나 확정 판정은 아님",
      "- 렌즈 반사 확인 모드로 현장 추가 확인 진행"
    ].join("\n"));
  };

  const downloadReport = () => {
    if (!reportText.trim()) return alert("먼저 신고 문안을 생성해주세요.");
    const blob = new Blob([reportText], { type: "text/plain;charset=utf-8" });
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = "safelens_report.txt";
    link.click();
    URL.revokeObjectURL(link.href);
  };

  return (
    <div className="phone-shell">
      <header className="appbar">
        <div className="appbar-left">
          <img className="appbar-logo" src="/app-icon.png" alt="SafeLens 아이콘" />
          <div className="appbar-title">SafeLens</div>
        </div>
        <div className="appbar-chip">Private Scan</div>
      </header>
      <main className="screen">
        {tab === "analyze" && (
          <section className="panel card border-0 shadow-sm">
            <h2 className="section-title">의심 장소 분석</h2>
            <input className="form-control" type="file" accept="image/*" onChange={onFileChange} />
            <div className="actions d-flex gap-2">
              <button className="btn btn-primary" onClick={analyzeImage} disabled={!hasImage}>AI 분석</button>
              <button className="btn btn-outline-secondary" onClick={() => { drawBaseImage(); setBoxes([]); }}>초기화</button>
            </div>
            <div className="canvas-wrap"><canvas ref={previewCanvasRef} /></div>
            <ul>
              {boxes.length === 0 && <li>의심 지점이 없거나 식별되지 않았습니다.</li>}
              {boxes.length > 0 && <li>의심 지점 {boxes.length}개가 표시되었습니다.</li>}
              {boxes.map((b, i) => <li key={`${i}-${b.x}`}>#{i + 1} 좌표 ({b.x}, {b.y})</li>)}
            </ul>
          </section>
        )}

        {tab === "scan" && (
          <section className="panel card border-0 shadow-sm">
            <h2 className="section-title">렌즈 반사 확인</h2>
            <div className="actions d-flex gap-2">
              <button className="btn btn-primary" onClick={startCamera} disabled={cameraOn}>시작</button>
              <button className="btn btn-outline-secondary" onClick={stopCamera} disabled={!cameraOn}>중지</button>
              <button className="btn btn-warning" onClick={toggleFlash} disabled={!cameraOn || !flashEnabled}>{torchOn ? "플래시 끄기" : "플래시"}</button>
            </div>
            <div className="camera-wrap"><video ref={videoRef} autoPlay playsInline muted /><canvas ref={overlayRef} id="overlay" /></div>
          </section>
        )}

        {tab === "report" && (
          <section className="panel card border-0 shadow-sm">
            <h2 className="section-title">신고 보조</h2>
            <input className="form-control" type="datetime-local" value={form.reportTime} onChange={(e) => setForm({ ...form, reportTime: e.target.value })} />
            <input className="form-control" type="text" placeholder="장소" value={form.reportPlace} onChange={(e) => setForm({ ...form, reportPlace: e.target.value })} />
            <textarea className="form-control" rows="4" placeholder="의심 정황" value={form.reportDesc} onChange={(e) => setForm({ ...form, reportDesc: e.target.value })} />
            <div className="actions d-flex gap-2">
              <button className="btn btn-primary" onClick={buildReport}>문안 생성</button>
              <button className="btn btn-outline-secondary" onClick={downloadReport}>저장</button>
              <a className="btn btn-danger" href="tel:112">112</a>
            </div>
            <textarea className="form-control" rows="9" readOnly value={reportText} placeholder="신고 문안" />
          </section>
        )}
      </main>

      <nav className="tabbar">
        <button
          aria-label="분석"
          className={`tab-icon-btn ${tab === "analyze" ? "active" : ""}`}
          onClick={() => setTab("analyze")}
        >
          ⌕
        </button>
        <button
          aria-label="확인"
          className={`tab-icon-btn ${tab === "scan" ? "active" : ""}`}
          onClick={() => setTab("scan")}
        >
          ◉
        </button>
        <button
          aria-label="신고"
          className={`tab-icon-btn ${tab === "report" ? "active" : ""}`}
          onClick={() => setTab("report")}
        >
          🚨
        </button>
      </nav>
    </div>
  );
}
