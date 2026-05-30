export function buildReportText(form) {
  return [
    "[몰래카메라 의심 신고 보조 문안]",
    `1. 발견 일시: ${form.reportTime || "(미입력)"}`,
    `2. 장소: ${form.reportPlace || "(미입력)"}`,
    "3. 의심 정황:",
    form.reportDesc || "(미입력)",
    "4. 앱 분석 안내:",
    "- 앱 분석은 의심 지점을 제시했으나 확정 판정은 아님",
    "- 렌즈 반사 확인 모드로 현장 추가 확인 진행"
  ].join("\n");
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

