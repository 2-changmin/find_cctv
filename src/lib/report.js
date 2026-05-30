export function buildReportText(form, boxes = [], options = {}) {
  const sensitivityLabel = options.sensitivity ? `감도: ${options.sensitivity}` : "감도: 미지정";
  const confidenceLabel = typeof options.minConfidence === "number" ? `최소 신뢰도: ${options.minConfidence}%` : "최소 신뢰도: 기본값";
  const sourceLabel = options.source ? options.source : "미지정";
  const lines = [
    "[몰래카메라 의심 신고 보조 문안]",
    `1. 발견 일시: ${form.reportTime || "(미입력)"}`,
    `2. 장소: ${form.reportPlace || "(미입력)"}`,
    `3. 분석 설정: ${sensitivityLabel} / ${confidenceLabel}`,
    `4. 분석 소스: ${sourceLabel}`,
    `5. 의심 정황:`,
    form.reportDesc || "(미입력)",
    "6. 앱 분석 안내:",
    "- 앱 분석은 의심 지점을 제시했으나 확정 판정은 아님",
    "- 렌즈 반사 확인 모드로 현장 추가 확인 진행"
  ];

  if (Array.isArray(boxes) && boxes.length) {
    lines.push("", "6. 앱 분석 결과:");
    lines.push(`- 총 후보 수: ${boxes.length}`);
    boxes.forEach((b, i) => {
      const coords = `(${Math.round(b.x)}, ${Math.round(b.y)}, ${Math.round(b.w)}, ${Math.round(b.h)})`;
      lines.push(`- 후보 #${i + 1}: ${b.type || "의심점"} · ${b.risk || "-"} · ${b.confidence || 0}% · 좌표 ${coords}`);
    });
    lines.push("", "(첨부된 캡처 이미지를 함께 제출하면 조사에 도움이 됩니다.)");
  }

  return lines.join("\n");
}

export function downloadTextFile(filename, content) {
  const blob = new Blob([content], { type: "text/plain;charset=utf-8" });
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = filename;
  link.click();
  URL.revokeObjectURL(link.href);
}

export function downloadCanvasImage(filename, canvas) {
  canvas.toBlob((blob) => {
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = filename;
    link.click();
    URL.revokeObjectURL(link.href);
  }, "image/png", 0.95);
}

export function buildReportHtml(form, boxes = [], canvas = null) {
  const text = buildReportText(form, boxes).replace(/\n/g, "<br />");
  let imgTag = "";
  try {
    if (canvas) {
      const dataUrl = canvas.toDataURL("image/png", 0.95);
      imgTag = `<div style="margin-top:12px;"><strong>첨부 이미지:</strong><br/><img src=\"${dataUrl}\" style=\"max-width:100%;height:auto;border:1px solid #ccc;\"/></div>`;
    }
  } catch (e) {
    // ignore dataURL errors (CORS) and proceed without image
    imgTag = "";
  }

  return `<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>SafeLens 신고 리포트</title>
  <style>body{font-family:system-ui,-apple-system,Segoe UI,Roboto,'Noto Sans KR',Arial;padding:16px;color:#111} pre{white-space:pre-wrap}</style>
</head>
<body>
  <h1>SafeLens 신고 리포트</h1>
  <div>${text}</div>
  ${imgTag}
</body>
</html>`;
}

export function downloadHtmlFile(filename, content) {
  const blob = new Blob([content], { type: "text/html;charset=utf-8" });
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = filename;
  link.click();
  URL.revokeObjectURL(link.href);
}

export async function buildReportZip(form, boxes = [], canvases = [], options = {}) {
  const JSZip = (await import("jszip")).default;
  const zip = new JSZip();
  const htmlText = buildReportText(form, boxes, {
    sensitivity: options.sensitivity,
    minConfidence: options.minConfidence,
    source: options.source
  }).replace(/\n/g, "<br />");

  const canvasItems = Array.isArray(canvases)
    ? canvases
    : canvases
    ? [{ canvas: canvases, label: "첨부 이미지" }]
    : [];

  const attachments = [];
  for (let i = 0; i < canvasItems.length; i += 1) {
    const item = canvasItems[i];
    if (!item?.canvas) continue;
    const blob = await new Promise((resolve) => item.canvas.toBlob(resolve, "image/png", 0.95));
    if (!blob) continue;
    const filename = `capture-${i + 1}.png`;
    zip.file(filename, blob);
    attachments.push({ filename, label: item.label });
  }

  const attachmentHtml = attachments
    .map(
      (item) =>
        `  <div style="margin-top:12px;"><strong>${item.label}:</strong><br/><img src="${item.filename}" alt="${item.label}"/></div>`
    )
    .join("\n");

  const reportBody = [
    "<!doctype html>",
    "<html lang=\"ko\">",
    "<head>",
    "  <meta charset=\"utf-8\" />",
    "  <meta name=\"viewport\" content=\"width=device-width,initial-scale=1\" />",
    "  <title>SafeLens 신고 리포트</title>",
    "  <style>body{font-family:system-ui,-apple-system,Segoe UI,Roboto,'Noto Sans KR',Arial;padding:16px;color:#111} img{max-width:100%;height:auto;border:1px solid #ccc;} </style>",
    "</head>",
    "<body>",
    "  <h1>SafeLens 신고 리포트</h1>",
    `  <div>${htmlText}</div>`,
    attachmentHtml,
    "</body>",
    "</html>"
  ]
    .filter(Boolean)
    .join("\n");

  zip.file("report.html", reportBody);
  return zip.generateAsync({ type: "blob" });
}

export function downloadZipFile(filename, blob) {
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = filename;
  link.click();
  URL.revokeObjectURL(link.href);
}

