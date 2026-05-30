import { useEffect, useMemo, useRef, useState } from "react";
import { detectSuspiciousSpots } from "./lib/detector";
import { fileToImage, setTorch, startRearCamera } from "./lib/media";
import { buildReportText, downloadTextFile, downloadCanvasImage, buildReportHtml, downloadHtmlFile } from "./lib/report";
import { reverseGeocode } from "./lib/geocode";

const TABS = {
  home: "home",
  analyze: "analyze",
  scan: "scan",
  report: "report"
};

const TAB_ITEMS = [
  { id: TABS.home, label: "홈", icon: "⌂" },
  { id: TABS.analyze, label: "분석", icon: "⌕" },
  { id: TABS.scan, label: "스캔", icon: "◉" },
  { id: TABS.report, label: "신고", icon: "!" }
];

function getCurrentDateTimeValue() {
  const now = new Date();
  const offset = now.getTimezoneOffset() * 60000;
  return new Date(now.getTime() - offset).toISOString().slice(0, 16);
}

function formatRiskSummary(boxes) {
  if (!boxes.length) return "탐지 전";
  const top = boxes[0];
  return `${top.risk} · ${top.confidence}%`;
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

  const [tab, setTab] = useState(TABS.home);
  const [boxes, setBoxes] = useState([]);
  const [liveBoxes, setLiveBoxes] = useState([]);
  const [cameraOn, setCameraOn] = useState(false);
  const [flashEnabled, setFlashEnabled] = useState(false);
  const [torchOn, setTorchOn] = useState(false);
  const [hasImage, setHasImage] = useState(false);
  const [sensitivity, setSensitivity] = useState("normal");
  const [status, setStatus] = useState("사진을 선택하거나 촬영한 뒤 분석을 실행하세요.");
  const [reportText, setReportText] = useState("");
  const [form, setForm] = useState({ reportTime: "", reportPlace: "", reportDesc: "" });

  const summary = useMemo(() => formatRiskSummary(boxes), [boxes]);
  const liveSummary = useMemo(() => formatRiskSummary(liveBoxes), [liveBoxes]);

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

  const analyzeImage = () => {
    const ctx = drawBaseImage();
    const canvas = previewCanvasRef.current;
    if (!ctx || !canvas) return;
    const nextBoxes = detectSuspiciousSpots(ctx, canvas.width, canvas.height, {
      maxResults: 6,
      sensitivity
    });
    drawBoxes(nextBoxes);
    setBoxes(nextBoxes);
    setStatus(nextBoxes.length ? `상위 의심 후보 ${nextBoxes.length}개를 표시했습니다.` : "뚜렷한 의심 후보가 식별되지 않았습니다.");
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
  };

  const startCamera = async () => {
    try {
      const stream = await startRearCamera(videoRef.current);
      streamRef.current = stream;
      videoTrackRef.current = stream.getVideoTracks()[0] || null;
      const capabilities =
        typeof videoTrackRef.current?.getCapabilities === "function" ? videoTrackRef.current.getCapabilities() : {};
      setFlashEnabled(Boolean(capabilities.torch));
      setCameraOn(true);
      setLiveBoxes([]);
      setStatus("실시간 렌즈 반사 확인을 시작했습니다.");
    } catch {
      setStatus("카메라 권한이 필요합니다. iPhone 설정 > 앱 > SafeLens에서 카메라를 허용하세요.");
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
    setLiveBoxes([]);
    setCameraOn(false);
    setFlashEnabled(false);
    setTorchOn(false);
  };

  const toggleFlash = async () => {
    const track = videoTrackRef.current;
    if (!track) return;
    try {
      const next = !torchOn;
      await setTorch(track, next);
      setTorchOn(next);
    } catch {
      setFlashEnabled(false);
      setStatus("현재 기기 또는 iOS WebView에서 플래시 제어를 지원하지 않습니다.");
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
      () => setStatus("위치 권한을 허용하면 현재 좌표를 자동 입력할 수 있습니다."),
      { enableHighAccuracy: true, timeout: 8000, maximumAge: 60000 }
    );
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
      const nextLiveBoxes = detectSuspiciousSpots(tctx, temp.width, temp.height, {
        maxResults: 5,
        sensitivity
      });
      setLiveBoxes(nextLiveBoxes);

      octx.lineWidth = 3;
      nextLiveBoxes.forEach((b, idx) => {
        octx.strokeStyle = markerColor(b.risk);
        octx.strokeRect(b.x, b.y, b.w, b.h);
        octx.fillStyle = markerColor(b.risk);
        octx.fillRect(b.x, Math.max(0, b.y - 20), 56, 20);
        octx.fillStyle = "#fff";
        octx.font = "14px sans-serif";
        octx.fillText(`${idx + 1} ${b.risk}`, b.x + 5, Math.max(15, b.y - 6));
      });
    }, 650);

    return () => scanTickRef.current && clearInterval(scanTickRef.current);
  }, [cameraOn]);

  useEffect(() => () => stopCamera(), []);

  const buildReport = () => {
    setReportText(buildReportText(form, boxes));
  };

  const downloadReport = () => {
    if (!reportText.trim()) {
      setStatus("먼저 신고 문안을 생성하세요.");
      return;
    }
    // Prefer embedding the analysis capture into an HTML report when a canvas is available
    const canvas = previewCanvasRef.current || overlayRef.current || null;
    if (canvas) {
      const timestamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, -5);
      const filename = `safelens_report-${timestamp}.html`;
      const html = buildReportHtml(form, boxes, canvas);
      downloadHtmlFile(filename, html);
      setStatus("이미지 포함 신고 리포트를 저장했습니다.");
      return;
    }

    downloadTextFile("safelens_report.txt", reportText);
  };

  return (
    <div className="phone-shell">
      <header className="appbar">
        <div className="appbar-left">
          <img className="appbar-logo" src="/app-icon.png" alt="SafeLens 아이콘" />
          <div>
            <div className="appbar-title">SafeLens</div>
            <div className="appbar-subtitle">몰래카메라 의심 위치 탐지 보조</div>
          </div>
        </div>
        <div className="appbar-chip">{cameraOn ? "Scanning" : "Private"}</div>
      </header>

      <main className="screen">
        {tab === TABS.home && (
          <section className="home-screen">
            <div className="home-hero">
              <img className="home-logo" src="/app-icon.png" alt="" />
              <h1>SafeLens</h1>
              <p>사진 분석과 실시간 반사 확인으로 의심 후보를 빠르게 표시합니다.</p>
            </div>
            <div className="quick-grid">
              <button className="quick-action primary" onClick={() => setTab(TABS.analyze)}>
                <span className="quick-icon">⌕</span>
                <span>사진 분석</span>
                <strong>{summary}</strong>
              </button>
              <button className="quick-action" onClick={() => setTab(TABS.scan)}>
                <span className="quick-icon">◉</span>
                <span>실시간 스캔</span>
                <strong>{liveSummary}</strong>
              </button>
              <button className="quick-action" onClick={() => setTab(TABS.report)}>
                <span className="quick-icon">!</span>
                <span>신고 보조</span>
                <strong>문안 생성</strong>
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
              <button className="btn btn-outline-primary" onClick={() => cameraInputRef.current?.click()}>
                촬영
              </button>
            </div>
            <input ref={libraryInputRef} className="visually-hidden" type="file" accept="image/*" onChange={onFileChange} />
            <input ref={cameraInputRef} className="visually-hidden" type="file" accept="image/*" capture="environment" onChange={onFileChange} />
            <div className="form-group">
              <label htmlFor="sensitivitySelect" className="form-label">탐지 민감도</label>
              <select
                id="sensitivitySelect"
                className="form-select"
                value={sensitivity}
                onChange={(event) => setSensitivity(event.target.value)}
              >
                <option value="low">낮음 (적은 오탐)</option>
                <option value="normal">보통</option>
                <option value="high">높음 (민감)</option>
              </select>
            </div>
            <div className="actions d-flex gap-2">
              <button className="btn btn-primary" onClick={analyzeImage} disabled={!hasImage}>
                분석
              </button>
              <button className="btn btn-outline-secondary" onClick={resetImage}>
                초기화
              </button>
              <button className="btn btn-success" onClick={saveAnalysisImage} disabled={boxes.length === 0}>
                💾 저장
              </button>
            </div>
            <div className="canvas-wrap">
              <canvas ref={previewCanvasRef} />
            </div>
            <p className="status-text">{status}</p>
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
          </section>
        )}

        {tab === TABS.scan && (
          <section className="panel">
            <div className="section-head">
              <h2 className="section-title">렌즈 반사 확인</h2>
              <span className="risk-pill">{liveSummary}</span>
            </div>
            <div className="actions d-flex gap-2">
              <button className="btn btn-primary" onClick={startCamera} disabled={cameraOn}>
                시작
              </button>
              <button className="btn btn-outline-secondary" onClick={stopCamera} disabled={!cameraOn}>
                중지
              </button>
              <button className="btn btn-warning" onClick={toggleFlash} disabled={!cameraOn || !flashEnabled}>
                {torchOn ? "끄기" : "플래시"}
              </button>
              <button className="btn btn-success" onClick={saveLiveCapture} disabled={!cameraOn || liveBoxes.length === 0}>
                💾 캡처
              </button>
            </div>
            <div className="camera-wrap">
              <video ref={videoRef} autoPlay playsInline muted />
              <canvas ref={overlayRef} id="overlay" />
            </div>
            <p className="status-text">
              {cameraOn ? `현재 후보 ${liveBoxes.length}개 · 색상은 위험도 기준입니다.` : "시작을 누르면 후면 카메라로 확인합니다."}
            </p>
          </section>
        )}

        {tab === TABS.report && (
          <section className="panel">
            <div className="section-head">
              <h2 className="section-title">신고 보조</h2>
              <span className="risk-pill">자동 입력</span>
            </div>
            <div className="actions d-flex gap-2">
              <button className="btn btn-outline-primary" onClick={fillCurrentTime}>
                현재 시간
              </button>
              <button className="btn btn-outline-primary" onClick={fillCurrentLocation}>
                현재 위치
              </button>
            </div>
            <input
              className="form-control"
              type="datetime-local"
              value={form.reportTime}
              onChange={(e) => setForm({ ...form, reportTime: e.target.value })}
            />
            <input
              className="form-control"
              type="text"
              placeholder="장소"
              value={form.reportPlace}
              onChange={(e) => setForm({ ...form, reportPlace: e.target.value })}
            />
            <textarea
              className="form-control"
              rows="4"
              placeholder="의심 정황"
              value={form.reportDesc}
              onChange={(e) => setForm({ ...form, reportDesc: e.target.value })}
            />
            <div className="actions d-flex gap-2">
              <button className="btn btn-primary" onClick={buildReport}>
                문안 생성
              </button>
              <button className="btn btn-outline-secondary" onClick={downloadReport}>
                저장
              </button>
              <a className="btn btn-danger" href="tel:112">
                112
              </a>
            </div>
            <textarea className="form-control" rows="9" readOnly value={reportText} placeholder="신고 문안" />
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
