export function buildReportText(form, boxes = []) {
  const lines = [
    "[몰래카메라 의심 신고 보조 문안]",
    `1. 발견 일시: ${form.reportTime || "(미입력)"}`,
    `2. 장소: ${form.reportPlace || "(미입력)"}`,
    "3. 의심 정황:",
    form.reportDesc || "(미입력)",
    "4. 앱 분석 안내:",
    "- 앱 분석은 의심 지점을 제시했으나 확정 판정은 아님",
    "- 렌즈 반사 확인 모드로 현장 추가 확인 진행"
  ];

  if (Array.isArray(boxes) && boxes.length) {
    lines.push("", "5. 앱 분석 결과:");
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

