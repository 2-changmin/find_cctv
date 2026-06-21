import { useEffect, useMemo, useRef, useState } from "react";
import { detectSuspiciousSpots } from "./lib/detector";
import { fileToImage, loadImage, setTorch, startRearCamera, openAppSettings } from "./lib/media";
import { buildReportText, downloadTextFile, downloadCanvasImage, buildReportZip, downloadZipFile } from "./lib/report";
import { reverseGeocode } from "./lib/geocode";

const TABS = {
  home: "home",
  analyze: "analyze",
  scan: "scan",
  report: "report",
  help: "help"
};

const TAB_ITEMS = [
  { id: TABS.home, label: "홈", icon: "⌂" },
  { id: TABS.analyze, label: "분석", icon: "⌕" },
  { id: TABS.scan, label: "스캔", icon: "◉" },
  { id: TABS.report, label: "신고", icon: "!" }
];

const HISTORY_KEY = "safelens-analysis-history";

function getCurrentDateTimeValue() {
  const now = new Date();
  const offset = now.getTimezoneOffset() * 60000;
  return new Date(now.getTime() - offset).toISOString().slice(0, 16);
}

function getTimeParts(value) {
  const base = value ? new Date(value) : new Date();
  const date = Number.isNaN(base.getTime()) ? new Date() : base;
  return {
    hour: String(date.getHours()).padStart(2, "0"),
    minute: String(date.getMinutes()).padStart(2, "0")
  };
}

function setTimePartValue(currentValue, part, value) {
  const base = currentValue ? new Date(currentValue) : new Date();
  const date = Number.isNaN(base.getTime()) ? new Date() : base;
  if (part === "hour") date.setHours(Number(value));
  if (part === "minute") date.setMinutes(Number(value));
  const offset = date.getTimezoneOffset() * 60000;
  return new Date(date.getTime() - offset).toISOString().slice(0, 16);
}

function formatRiskSummary(boxes) {
  if (!boxes.length) return "탐지 전";
  const top = boxes[0];
  return `${top.risk} · ${top.confidence}%`;
}

function riskFromConfidence(confidence) {
  if (confidence >= 78) return "높음";
  if (confidence >= 62) return "주의";
  return "낮음";
}

export default function App() {
  const previewCanvasRef = useRef(null);
  const videoRef = useRef(null);
  const overlayRef = useRef(null);
  const libraryInputRef = useRef(null);
  const cameraInputRef = useRef(null);
  const loadedImgRef = useRef(null);
  const streamRef = useRef(null);
  const videoTrackRef = useRef(null);
  const scanTickRef = useRef(null);
  const scanHistoryRef = useRef([]);
  const scanFrameRef = useRef(null);
  const flashPairRef = useRef({ phase: "captureOff", offFrame: null });
  const scanBusyRef = useRef(false);
  const liveBoxesRef = useRef([]);

  const [tab, setTab] = useState(TABS.home);
  const [boxes, setBoxes] = useState([]);
  const [liveBoxes, setLiveBoxes] = useState([]);
  const [cameraOn, setCameraOn] = useState(false);
  const [flashEnabled, setFlashEnabled] = useState(false);
  const [torchOn, setTorchOn] = useState(false);
  const [scanMode, setScanMode] = useState("대기");
  const [hasImage, setHasImage] = useState(false);
  const [sensitivity, setSensitivity] = useState("normal");
  const [minConfidence, setMinConfidence] = useState(40);
  const [status, setStatus] = useState("사진을 선택하거나 촬영한 뒤 분석을 실행하세요.");
  const [showSettingsButton, setShowSettingsButton] = useState(false);
  const [reportText, setReportText] = useState("");
  const [history, setHistory] = useState([]);
  const [form, setForm] = useState({ reportTime: "", reportPlace: "", reportDesc: "" });

  useEffect(() => {
    try {
      const raw = localStorage.getItem(HISTORY_KEY);
      if (raw) {
        setHistory(JSON.parse(raw));
      }
    } catch {
      // ignore local storage errors
    }
  }, []);

  const persistHistory = (items) => {
    setHistory(items);
    try {
      localStorage.setItem(HISTORY_KEY, JSON.stringify(items));
    } catch {
      // ignore local storage errors
    }
  };

  const addHistoryEntry = (entry) => {
    const next = [entry, ...history].slice(0, 10);
    persistHistory(next);
  };

  const loadHistoryItem = async (item) => {
    if (!item?.imageUrl) {
      setStatus("저장된 분석 결과를 불러올 수 없습니다.");
      return;
    }

    try {
      let img;
      if (typeof item.imageUrl === "string" && item.imageUrl.startsWith("data:")) {
        img = await loadImage(item.imageUrl);
      } else {
        const response = await fetch(item.imageUrl);
        const blob = await response.blob();
        img = await fileToImage(new File([blob], "history.png", { type: blob.type }));
      }

      loadedImgRef.current = img;
      setBoxes(item.boxes || []);
      setHasImage(true);
      setTab(TABS.analyze);
      setStatus(`저장된 ${item.source} 결과를 불러왔습니다.`);
      requestAnimationFrame(() => {
        const ctx = drawBaseImage();
        if (ctx) drawBoxes(item.boxes || []);
      });
    } catch {
      setStatus("저장된 분석 결과를 불러오는 중 오류가 발생했습니다.");
    }
  };

  const summary = useMemo(() => formatRiskSummary(boxes), [boxes]);
  const liveSummary = useMemo(() => formatRiskSummary(liveBoxes), [liveBoxes]);
  const reportTimeParts = useMemo(() => getTimeParts(form.reportTime), [form.reportTime]);

  useEffect(() => {
    liveBoxesRef.current = liveBoxes;
  }, [liveBoxes]);

  const drawBaseImage = () => {
    const canvas = previewCanvasRef.current;
    const img = loadedImgRef.current;
    if (!canvas || !img) return null;
    const ctx = canvas.getContext("2d");
    const ratio = img.width / img.height;
    const targetW = Math.min(1000, img.width);
    const targetH = Math.round(targetW / ratio);
    canvas.width = targetW;
    canvas.height = targetH;
    ctx.drawImage(img, 0, 0, targetW, targetH);
    return ctx;
  };

  const markerColor = (risk) => {
    if (risk === "높음") return "#ef4444";
    if (risk === "주의") return "#f59e0b";
    return "#38bdf8";
  };

  const drawBoxes = (nextBoxes) => {
    const canvas = previewCanvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    ctx.lineWidth = 2;
    ctx.font = "12px sans-serif";
    nextBoxes.forEach((b, idx) => {
      const label = `${idx + 1} ${b.risk}`;
      const tw = ctx.measureText(label).width + 10;
      ctx.strokeStyle = markerColor(b.risk);
      ctx.strokeRect(b.x, b.y, b.w, b.h);
      ctx.fillStyle = markerColor(b.risk);
      ctx.fillRect(b.x, Math.max(0, b.y - 18), tw, 18);
      ctx.fillStyle = "#fff";
      ctx.fillText(label, b.x + 5, Math.max(13, b.y - 5));
    });
  };

  const setLoadedImage = (img) => {
    loadedImgRef.current = img;
    setBoxes([]);
    setHasImage(true);
    setStatus("이미지를 불러왔습니다. 분석을 실행하세요.");
    requestAnimationFrame(drawBaseImage);
  };

  const onFileChange = async (event) => {
    const file = event.target.files?.[0];
    if (!file) return;
    try {
      const img = await fileToImage(file);
      setLoadedImage(img);
    } catch {
      setStatus("이미지를 불러오지 못했습니다.");
    } finally {
      event.target.value = "";
    }
  };

  const analyzeImage = async () => {
    const ctx = drawBaseImage();
    const canvas = previewCanvasRef.current;
    if (!ctx || !canvas) return;
    const nextBoxes = detectSuspiciousSpots(ctx, canvas.width, canvas.height, {
      maxResults: 6,
      sensitivity,
      minConfidence
    });
    drawBoxes(nextBoxes);
    setBoxes(nextBoxes);
    setStatus(nextBoxes.length ? `상위 의심 후보 ${nextBoxes.length}개를 표시했습니다.` : "뚜렷한 의심 후보가 식별되지 않았습니다.");

    try {
      const entry = {
        id: `analysis-${Date.now()}`,
        createdAt: new Date().toISOString(),
        source: "사진 분석",
        boxes: nextBoxes,
        imageUrl: canvas.toDataURL("image/png", 0.7)
      };
      addHistoryEntry(entry);
    } catch {
      // ignore history save errors
    }
  };

  const resetImage = () => {
    drawBaseImage();
    setBoxes([]);
    setStatus(hasImage ? "분석 표시를 초기화했습니다." : "사진을 선택하거나 촬영한 뒤 분석을 실행하세요.");
  };

  const saveAnalysisImage = () => {
    const canvas = previewCanvasRef.current;
    if (!canvas) return;
    const timestamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, -5);
    const filename = `safelens-analysis-${timestamp}.png`;
    downloadCanvasImage(filename, canvas);
    setStatus("분석 결과 이미지를 저장했습니다.");
  };

  const saveLiveCapture = () => {
    const canvas = overlayRef.current;
    if (!canvas) return;
    const timestamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, -5);
    const filename = `safelens-scan-${timestamp}.png`;
    downloadCanvasImage(filename, canvas);
    setStatus("실시간 스캔 캡처를 저장했습니다.");

    try {
      const entry = {
        id: `scan-${Date.now()}`,
        createdAt: new Date().toISOString(),
        source: "실시간 스캔",
        boxes: liveBoxes,
        imageUrl: canvas.toDataURL("image/png", 0.7)
      };
      addHistoryEntry(entry);
    } catch {
      // ignore history save errors
    }
  };

  const startCamera = async () => {
    try {
      const stream = await startRearCamera(videoRef.current);
      streamRef.current = stream;
      videoTrackRef.current = stream.getVideoTracks()[0] || null;
      const capabilities =
        typeof videoTrackRef.current?.getCapabilities === "function" ? videoTrackRef.current.getCapabilities() : {};
      const supportsTorch = Boolean(capabilities.torch);
      setFlashEnabled(supportsTorch);
      if (supportsTorch) {
        await setTorch(videoTrackRef.current, false);
      }
      setCameraOn(true);
      setLiveBoxes([]);
      scanHistoryRef.current = [];
      scanFrameRef.current = null;
      flashPairRef.current = { phase: "captureOff", offFrame: null };
      scanBusyRef.current = false;
      setTorchOn(false);
      setScanMode(supportsTorch ? "자동 플래시 차분" : "연속 프레임 차분");
      setShowSettingsButton(false);
      setStatus(supportsTorch ? "자동 플래시 OFF/ON 차분 스캔을 시작했습니다." : "플래시 제어가 없어 연속 프레임 차분으로 스캔합니다.");
    } catch {
      setShowSettingsButton(true);
      setStatus("카메라 권한을 허용해야 실시간 스캔을 사용할 수 있습니다. 설정으로 이동하세요.");
    }
  };

  const stopCamera = () => {
    if (scanTickRef.current) clearInterval(scanTickRef.current);
    scanTickRef.current = null;
    scanHistoryRef.current = [];
    scanFrameRef.current = null;
    flashPairRef.current = { phase: "captureOff", offFrame: null };
    scanBusyRef.current = false;
    if (streamRef.current) streamRef.current.getTracks().forEach((track) => track.stop());
    streamRef.current = null;
    if (videoRef.current) videoRef.current.srcObject = null;
    if (overlayRef.current) {
      const octx = overlayRef.current.getContext("2d");
      octx.clearRect(0, 0, overlayRef.current.width, overlayRef.current.height);
    }
    setLiveBoxes([]);
    setCameraOn(false);
    setFlashEnabled(false);
    setTorchOn(false);
    setScanMode("대기");
  };

  const openSettings = async () => {
    const opened = await openAppSettings();
    if (opened) {
      setStatus("설정 화면을 열었습니다. 거기에서 권한을 허용해주세요.");
    } else {
      setStatus("설정 화면을 열 수 없습니다. 앱 설정으로 이동하여 권한을 허용해주세요.");
    }
  };

  const fillCurrentTime = () => {
    setForm((prev) => ({ ...prev, reportTime: getCurrentDateTimeValue() }));
  };

  const fillCurrentLocation = () => {
    if (!navigator.geolocation) {
      setStatus("이 기기에서 위치 정보를 지원하지 않습니다.");
      return;
    }
    navigator.geolocation.getCurrentPosition(
      async (pos) => {
        const lat = pos.coords.latitude.toFixed(6);
        const lng = pos.coords.longitude.toFixed(6);
        setShowSettingsButton(false);
        setStatus("주소 변환 중...");
        try {
          const address = await reverseGeocode(lat, lng);
          setForm((prev) => ({ ...prev, reportPlace: `${address} (${lat}, ${lng})` }));
          setStatus("현재 위치 주소를 신고 문안에 입력했습니다.");
        } catch (e) {
          setForm((prev) => ({ ...prev, reportPlace: `현재 위치 (${lat}, ${lng})` }));
          setStatus("좌표를 신고 문안에 입력했습니다. (주소 변환 실패)");
        }
      },
      (err) => {
        setShowSettingsButton(true);
        if (err?.code === 1) {
          setStatus("위치 권한을 거부했습니다. 설정에서 위치 사용을 허용하세요.");
        } else {
          setStatus("위치 권한을 허용하면 현재 좌표를 자동 입력할 수 있습니다.");
        }
      },
      { enableHighAccuracy: true, timeout: 8000, maximumAge: 60000 }
    );
  };

  const getActiveReportData = () => {
    const canvases = [];
    if (previewCanvasRef.current) canvases.push({ canvas: previewCanvasRef.current, label: "분석 결과 이미지" });
    if (overlayRef.current) canvases.push({ canvas: overlayRef.current, label: "실시간 스캔 캡처" });

    if (boxes.length) {
      return { boxes, canvases, source: "사진 분석" };
    }
    if (liveBoxes.length) {
      return { boxes: liveBoxes, canvases, source: "실시간 스캔" };
    }
    return { boxes: [], canvases, source: "분석 없음" };
  };

  const mergeScanFrames = (nextBoxes) => {
    const history = scanHistoryRef.current;
    history.push(nextBoxes);
    if (history.length > 6) history.shift();
    if (history.length < 2) return [];

    const frames = history.slice(-5);
    const clusters = [];

    frames.forEach((frame, frameIndex) => {
      frame.forEach((box) => {
        const cx = box.x + box.w / 2;
        const cy = box.y + box.h / 2;
        const match = clusters.find((cluster) => {
          const dist = Math.hypot(cluster.cx - cx, cluster.cy - cy);
          return (
            dist < Math.max(30, Math.min(cluster.w, box.w) * 0.35) &&
            Math.abs(cluster.w - box.w) < Math.max(20, cluster.w * 0.4) &&
            Math.abs(cluster.h - box.h) < Math.max(20, cluster.h * 0.4)
          );
        });

        if (match) {
          match.count += 1;
          match.sumX += box.x;
          match.sumY += box.y;
          match.sumW += box.w;
          match.sumH += box.h;
          match.cx = match.sumX / match.count + match.sumW / match.count / 2;
          match.cy = match.sumY / match.count + match.sumH / match.count / 2;
          match.framesSeen.add(frameIndex);
          match.sumConfidence += box.confidence ?? 0;
          if ((box.confidence ?? 0) > (match.bestConfidence ?? 0)) {
            match.best = box;
            match.bestConfidence = box.confidence ?? 0;
          }
        } else {
          clusters.push({
            cx,
            cy,
            count: 1,
            sumX: box.x,
            sumY: box.y,
            sumW: box.w,
            sumH: box.h,
            w: box.w,
            h: box.h,
            best: box,
            bestConfidence: box.confidence ?? 0,
            sumConfidence: box.confidence ?? 0,
            framesSeen: new Set([frameIndex])
          });
        }
      });
    });

    const minFrameCount = Math.max(2, Math.ceil(frames.length * 0.45));
    return clusters
      .filter((cluster) => cluster.framesSeen.size >= minFrameCount)
      .map((cluster) => {
        const persistence = cluster.framesSeen.size / frames.length;
        const averageConfidence = cluster.sumConfidence / Math.max(1, cluster.count);
        const confidence = Math.round(Math.min(99, cluster.bestConfidence * 0.72 + averageConfidence * 0.18 + persistence * 10));
        return {
          x: Math.round(cluster.sumX / cluster.count),
          y: Math.round(cluster.sumY / cluster.count),
          w: Math.round(cluster.sumW / cluster.count),
          h: Math.round(cluster.sumH / cluster.count),
          risk: riskFromConfidence(confidence),
          confidence,
          type: cluster.best.type,
          reason: cluster.best.reason,
          evidence: {
            ...(cluster.best.evidence || {}),
            persistence: Math.round(persistence * 100)
          }
        };
      })
      .sort((a, b) => b.confidence - a.confidence);
  };

  useEffect(() => {
    if (!cameraOn) return undefined;
    scanTickRef.current = setInterval(async () => {
      if (scanBusyRef.current) return;
      if (!videoRef.current?.videoWidth || !overlayRef.current) return;
      scanBusyRef.current = true;
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
      const frameData = tctx.getImageData(0, 0, temp.width, temp.height);

      let nextLiveBoxes = [];
      let stableBoxes = liveBoxesRef.current;

      try {
        const track = videoTrackRef.current;
        if (flashEnabled && track) {
          const pair = flashPairRef.current;
          if (pair.phase === "captureOff") {
            pair.offFrame = frameData;
            pair.phase = "captureOn";
            await setTorch(track, true);
            setTorchOn(true);
            setScanMode("기준 프레임 저장");
            scanBusyRef.current = false;
            return;
          }

          nextLiveBoxes = detectSuspiciousSpots(tctx, temp.width, temp.height, {
            maxResults: 5,
            sensitivity,
            minConfidence,
            liveMode: true,
            imageData: frameData,
            previousImageData: pair.offFrame
          });
          pair.offFrame = null;
          pair.phase = "captureOff";
          await setTorch(track, false);
          setTorchOn(false);
          setScanMode("자동 플래시 차분");
        } else {
          nextLiveBoxes = detectSuspiciousSpots(tctx, temp.width, temp.height, {
            maxResults: 5,
            sensitivity,
            minConfidence,
            liveMode: true,
            imageData: frameData,
            previousImageData: scanFrameRef.current
          });
          scanFrameRef.current = frameData;
          setScanMode("연속 프레임 차분");
        }

        stableBoxes = mergeScanFrames(nextLiveBoxes);
        setLiveBoxes(stableBoxes);
      } catch {
        setFlashEnabled(false);
        setTorchOn(false);
        flashPairRef.current = { phase: "captureOff", offFrame: null };
        scanFrameRef.current = frameData;
        setScanMode("연속 프레임 차분");
        setStatus("플래시 자동 제어가 실패해 연속 프레임 차분으로 전환했습니다.");
      }

      octx.lineWidth = 3;
      stableBoxes.forEach((b, idx) => {
        octx.strokeStyle = markerColor(b.risk);
        octx.strokeRect(b.x, b.y, b.w, b.h);
        octx.fillStyle = markerColor(b.risk);
        octx.fillRect(b.x, Math.max(0, b.y - 20), 56, 20);
        octx.fillStyle = "#fff";
        octx.font = "14px sans-serif";
        octx.fillText(`${idx + 1} ${b.risk}`, b.x + 5, Math.max(15, b.y - 6));
      });
      scanBusyRef.current = false;
    }, flashEnabled ? 650 : 500);

    return () => scanTickRef.current && clearInterval(scanTickRef.current);
  }, [cameraOn, sensitivity, minConfidence, flashEnabled]);

  useEffect(() => () => stopCamera(), []);

  const buildReport = () => {
    const { boxes: reportBoxes, source } = getActiveReportData();
    const nextForm = form.reportTime ? form : { ...form, reportTime: getCurrentDateTimeValue() };
    if (nextForm !== form) {
      setForm(nextForm);
    }
    setReportText(buildReportText(nextForm, reportBoxes, { sensitivity, minConfidence, source }));
  };

  const downloadReport = async () => {
    const { boxes: reportBoxes, canvases, source } = getActiveReportData();
    if (!reportText.trim()) {
      setReportText(buildReportText(form, reportBoxes, { sensitivity, minConfidence, source }));
    }
    const timestamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, -5);
    const filename = `safelens_report-${timestamp}.zip`;
    const zipBlob = await buildReportZip(form, reportBoxes, canvases, { sensitivity, minConfidence, source });
    downloadZipFile(filename, zipBlob);
    setStatus("현재 분석 이미지와 후보 정보를 포함한 신고 리포트를 ZIP으로 저장했습니다.");
  };

  return (
    <div className="phone-shell">
      <header className="appbar">
        <div className="appbar-left">
          <img className="appbar-logo" src="/app-icon.png" alt="SafeLens 아이콘" />
          <div>
            <div className="appbar-title">SafeLens</div>
            <div className="appbar-subtitle">의심 위치 확인 보조</div>
          </div>
        </div>
        <div className="appbar-chip">{cameraOn ? "Scan" : "Local"}</div>
      </header>

      <main className="screen">
        {tab === TABS.home && (
          <section className="home-screen">
            <div className="home-hero">
              <img className="home-logo" src="/app-icon.png" alt="" />
              <h1>SafeLens</h1>
              <p>현장 확인과 신고 준비를 한 화면 흐름으로 정리합니다.</p>
              <div className="hero-stat-row" aria-label="현재 분석 상태">
                <span>
                  <strong>{boxes.length}</strong>
                  사진 후보
                </span>
                <span>
                  <strong>{liveBoxes.length}</strong>
                  스캔 후보
                </span>
              </div>
            </div>
            <div className="quick-grid">
              <button className="quick-action primary" onClick={() => setTab(TABS.analyze)}>
                <span className="quick-icon">⌕</span>
                <span>
                  <b>사진 분석</b>
                  <small>이미지에서 의심 후보 표시</small>
                </span>
                <strong>탐지 전 <span aria-hidden="true">›</span></strong>
              </button>
              <button className="quick-action" onClick={() => setTab(TABS.scan)}>
                <span className="quick-icon">◉</span>
                <span>
                  <b>실시간 스캔</b>
                  <small>렌즈 반사 확인</small>
                </span>
                <strong>탐지 전 <span aria-hidden="true">›</span></strong>
              </button>
              <button className="quick-action" onClick={() => setTab(TABS.report)}>
                <span className="quick-icon">!</span>
                <span>
                  <b>신고 보조</b>
                  <small>문안 생성</small>
                </span>
                <strong>문안 생성 <span aria-hidden="true">›</span></strong>
              </button>
              <button className="quick-action" onClick={() => setTab(TABS.help)}>
                <span className="quick-icon">☞</span>
                <span>
                  <b>도움 받기</b>
                  <small>대처 안내</small>
                </span>
                <strong>대처 안내 <span aria-hidden="true">›</span></strong>
              </button>
            </div>
            <div className="notice-band">앱 결과는 확정 판정이 아니라 신고와 현장 확인을 돕는 참고 정보입니다.</div>
          </section>
        )}

        {tab === TABS.analyze && (
          <section className="panel">
            <div className="section-head">
              <h2 className="section-title">의심 장소 분석</h2>
              <span className="risk-pill">{summary}</span>
            </div>
            <div className="actions action-grid">
              <button className="btn btn-primary" onClick={() => libraryInputRef.current?.click()}>
                사진 선택
              </button>
              <button className="btn btn-outline-secondary" onClick={resetImage}>초기화</button>
            </div>
            <button className="btn btn-outline-primary btn-block" onClick={analyzeImage} disabled={!hasImage}>
              분석
            </button>
            <input ref={libraryInputRef} className="visually-hidden" type="file" accept="image/*" onChange={onFileChange} />
            <input ref={cameraInputRef} className="visually-hidden" type="file" accept="image/*" capture="environment" onChange={onFileChange} />
            <div className="canvas-wrap">
              <canvas ref={previewCanvasRef} />
              {!hasImage && <span className="media-placeholder">선택한 이미지가 여기에 표시됩니다.</span>}
            </div>
            <p className="status-text">{status}</p>
            {showSettingsButton && (
              <button className="btn btn-link" onClick={openSettings}>
                설정 열기
              </button>
            )}
            <div className="result-list">
              {boxes.length === 0 && <div className="empty-state">분석 결과가 여기에 표시됩니다.</div>}
              {boxes.map((b, i) => (
                <div className={`result-card risk-${b.risk}`} key={`${i}-${b.x}`}>
                  <div>
                    <strong>#{i + 1} {b.type}</strong>
                    <span>{b.reason}</span>
                  </div>
                  <div className="risk-score">
                    <b>{b.risk}</b>
                    <small>{b.confidence}%</small>
                  </div>
                </div>
              ))}
            </div>
            {history.length > 0 && (
              <section className="panel mt-3">
                <div className="section-head">
                  <h3 className="section-title">분석 기록</h3>
                </div>
                <div className="history-list">
                  {history.map((item) => (
                    <button
                      key={item.id}
                      type="button"
                      className="history-item btn btn-outline-secondary mb-2 w-100 text-start"
                      onClick={() => loadHistoryItem(item)}
                    >
                      <div><strong>{item.source}</strong> · {item.boxes?.length || 0}개 후보</div>
                      <div className="small text-muted">{new Date(item.createdAt).toLocaleString()}</div>
                    </button>
                  ))}
                </div>
              </section>
            )}
          </section>
        )}

        {tab === TABS.scan && (
          <section className="panel">
            <div className="section-head">
              <h2 className="section-title">렌즈 반사 확인</h2>
              <span className="risk-pill">{liveSummary}</span>
            </div>
            <p className="section-desc">플래시 반사 후보를 실시간으로 표시합니다. 표시된 지점은 확정 판정이 아니라 확인용 참고 정보입니다.</p>
            <div className="actions scan-actions">
              <button className="btn btn-primary" onClick={startCamera} disabled={cameraOn}>
                시작
              </button>
              <button className="btn btn-outline-secondary" onClick={stopCamera} disabled={!cameraOn}>
                중지
              </button>
              <button className="btn btn-warning" disabled>
                {cameraOn && flashEnabled ? (torchOn ? "ON" : "OFF") : "플래시"}
              </button>
            </div>
            <div className="camera-wrap">
              <video ref={videoRef} autoPlay playsInline muted />
              <canvas ref={overlayRef} id="overlay" />
              {!cameraOn && <span className="media-placeholder">카메라 시작 후 이곳에서 반사 확인</span>}
            </div>
            <p className="status-text">
              {showSettingsButton
                ? status
                : cameraOn
                ? `${scanMode} · 현재 후보 ${liveBoxes.length}개 · 반복 확인된 위치만 표시합니다.`
                : "시작을 누르면 후면 카메라로 확인합니다."}
            </p>
            {showSettingsButton && (
              <button className="btn btn-link" onClick={openSettings}>
                설정 열기
              </button>
            )}
          </section>
        )}

        {tab === TABS.report && (
          <section className="panel">
            <div className="section-head">
              <h2 className="section-title">신고 보조</h2>
              <span className="risk-pill">문안 생성</span>
            </div>
            <div className="time-row">
              <label className="time-select">
                <span>발견 시각</span>
                <select
                  className="form-select"
                  value={reportTimeParts.hour}
                  onChange={(e) => setForm({ ...form, reportTime: setTimePartValue(form.reportTime, "hour", e.target.value) })}
                >
                  {Array.from({ length: 24 }, (_, i) => String(i).padStart(2, "0")).map((hour) => (
                    <option key={hour} value={hour}>{Number(hour)}</option>
                  ))}
                </select>
                <span>시</span>
              </label>
              <label className="time-select">
                <select
                  className="form-select"
                  value={reportTimeParts.minute}
                  onChange={(e) => setForm({ ...form, reportTime: setTimePartValue(form.reportTime, "minute", e.target.value) })}
                >
                  {Array.from({ length: 12 }, (_, i) => String(i * 5).padStart(2, "0")).map((minute) => (
                    <option key={minute} value={minute}>{Number(minute)}</option>
                  ))}
                </select>
                <span>분</span>
              </label>
            </div>
            {showSettingsButton && (
              <button className="btn btn-link" onClick={openSettings}>
                설정 열기
              </button>
            )}
            <input
              className="form-control"
              type="text"
              placeholder="현재 위치 또는 장소"
              value={form.reportPlace}
              onChange={(e) => setForm({ ...form, reportPlace: e.target.value })}
              onFocus={() => {
                if (!form.reportPlace) fillCurrentLocation();
              }}
            />
            <textarea
              className="form-control"
              rows="4"
              placeholder="의심 정황"
              value={form.reportDesc}
              onChange={(e) => setForm({ ...form, reportDesc: e.target.value })}
            />
            <div className="actions report-actions">
              <button className="btn btn-primary" onClick={buildReport}>
                문안 생성
              </button>
              <button className="btn btn-outline-secondary" onClick={downloadReport}>
                저장
              </button>
              <a className="btn btn-outline-secondary" href={`sms:?body=${encodeURIComponent(reportText || "몰래카메라 의심 신고를 요청합니다.")}`}>
                문자 신고
              </a>
              <a className="btn btn-danger" href="tel:112">
                112
              </a>
            </div>
            <p className="form-text">문안 생성 후 문자 신고 또는 112 전화 신고를 선택할 수 있습니다.</p>
            <button className="btn btn-outline-secondary btn-block" onClick={() => setTab(TABS.help)}>
              피해 대처 안내 보기
            </button>
            <textarea className="form-control" rows="9" readOnly value={reportText} placeholder="신고 문안" />
          </section>
        )}

        {tab === TABS.help && (
          <section className="panel help-panel">
            <div className="section-head">
              <h2 className="section-title">도움 받기</h2>
              <span className="risk-pill">대처 안내</span>
            </div>
            <p className="section-desc">불안하거나 피해가 의심될 때 바로 확인할 수 있는 대응 순서입니다.</p>
            <div className="help-list">
              <article className="help-card">
                <span className="help-icon">✱</span>
                <h3>지금 바로 할 일</h3>
                <ul>
                  <li>긴급하거나 위험하면 즉시 112로 신고합니다.</li>
                  <li>가능하면 안전한 장소로 이동하고 주변에 도움을 요청합니다.</li>
                  <li>가해자와 직접 대면하거나 혼자 삭제를 요구하지 않습니다.</li>
                </ul>
                <div className="help-actions">
                  <a className="btn btn-outline-danger" href="tel:112">112 전화</a>
                  <a className="btn btn-outline-secondary" href="tel:1366">1366 전화</a>
                </div>
              </article>
              <article className="help-card">
                <span className="help-icon">▤</span>
                <h3>증거 보존</h3>
                <ul>
                  <li>게시물 URL, 계정명, 업로드 시각, 캡처 화면을 보관합니다.</li>
                  <li>가능하면 원본 파일과 화면 녹화도 따로 보관합니다.</li>
                  <li>신고나 삭제 요청 전 증거가 사라지지 않도록 먼저 정리합니다.</li>
                  <li>불법촬영물을 불필요하게 재전송하거나 공유하지 않습니다.</li>
                </ul>
              </article>
              <article className="help-card">
                <span className="help-icon">▥</span>
                <h3>공공 지원</h3>
                <ul>
                  <li>중앙디지털성범죄피해자지원센터에서 상담, 삭제지원, 모니터링, 수사·법률·의료 연계를 받을 수 있습니다.</li>
                  <li>여성긴급전화 1366은 365일 24시간 초기 상담을 지원합니다.</li>
                  <li>지역 디지털성범죄피해자지원센터도 상담과 삭제 연계를 제공합니다.</li>
                </ul>
                <div className="help-actions">
                  <a className="btn btn-outline-secondary" href="https://d4u.stop.or.kr" target="_blank" rel="noreferrer">센터 열기</a>
                  <a className="btn btn-outline-secondary" href="tel:1366">지역 센터</a>
                </div>
              </article>
              <article className="help-card">
                <span className="help-icon">▦</span>
                <h3>삭제 지원</h3>
                <ul>
                  <li>우선 공공기관의 삭제지원과 모니터링을 확인합니다.</li>
                  <li>민간 삭제 대행 서비스는 비용, 환불 조건, 삭제 가능 범위, 개인정보 제공 범위를 확인해야 합니다.</li>
                  <li>앱에서는 이런 서비스를 디지털 장의사 또는 온라인 게시물 삭제 대행으로 안내할 수 있습니다.</li>
                </ul>
              </article>
              <article className="help-card">
                <span className="help-icon">♡</span>
                <h3>법률·심리 지원</h3>
                <ul>
                  <li>수사 진행, 법률 상담, 의료 지원, 심리 상담을 함께 요청할 수 있습니다.</li>
                  <li>혼자 판단하기 어렵다면 상담기관을 통해 필요한 기관으로 연계받는 방식이 안전합니다.</li>
                </ul>
              </article>
            </div>
          </section>
        )}
      </main>

      <nav className="tabbar">
        {TAB_ITEMS.map((item) => (
          <button
            key={item.id}
            aria-label={item.label}
            className={`tab-icon-btn ${tab === item.id ? "active" : ""}`}
            onClick={() => setTab(item.id)}
          >
            <span className="tab-symbol">{item.icon}</span>
            <span className="tab-label">{item.label}</span>
          </button>
        ))}
      </nav>
    </div>
  );
}
