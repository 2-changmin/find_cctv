import { Capacitor } from "@capacitor/core";
import { Camera, CameraResultType, CameraSource } from "@capacitor/camera";

export function isNativeApp() {
  return Capacitor.isNativePlatform();
}

function isAllowed(state) {
  return state === "granted" || state === "limited";
}

export async function ensureCameraPermission() {
  if (!isNativeApp()) return true;

  const current = await Camera.checkPermissions();
  if (isAllowed(current.camera)) return true;

  const requested = await Camera.requestPermissions({ permissions: ["camera"] });
  return isAllowed(requested.camera);
}

export async function ensurePhotoPermission() {
  if (!isNativeApp()) return true;

  const current = await Camera.checkPermissions();
  if (isAllowed(current.photos)) return true;

  const requested = await Camera.requestPermissions({ permissions: ["photos"] });
  return isAllowed(requested.photos);
}

export async function pickNativePhoto() {
  const allowed = await ensurePhotoPermission();
  if (!allowed) {
    throw new Error("photo-permission-denied");
  }

  const photo = await Camera.getPhoto({
    quality: 90,
    resultType: CameraResultType.Uri,
    source: CameraSource.Photos,
    width: 1600
  });
  return photo.webPath;
}

export async function captureNativePhoto() {
  const allowed = await ensureCameraPermission();
  if (!allowed) {
    throw new Error("camera-permission-denied");
  }

  const photo = await Camera.getPhoto({
    quality: 90,
    resultType: CameraResultType.Uri,
    source: CameraSource.Camera,
    width: 1600,
    saveToGallery: false
  });
  return photo.webPath;
}

export function loadImage(src) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = reject;
    img.src = src;
  });
}

export async function fileToImage(file) {
  const url = URL.createObjectURL(file);
  try {
    return await loadImage(url);
  } finally {
    setTimeout(() => URL.revokeObjectURL(url), 0);
  }
}

export async function startRearCamera(videoEl) {
  const allowed = await ensureCameraPermission();
  if (!allowed) {
    throw new Error("camera-permission-denied");
  }

  if (!navigator.mediaDevices?.getUserMedia) {
    throw new Error("이 기기에서는 실시간 카메라 스트림을 지원하지 않습니다.");
  }

  const stream = await navigator.mediaDevices.getUserMedia({
    video: {
      facingMode: { ideal: "environment" },
      width: { ideal: 1280 },
      height: { ideal: 720 }
    },
    audio: false
  });

  videoEl.srcObject = stream;
  await videoEl.play();
  return stream;
}

export async function setTorch(track, enabled) {
  const capabilities = typeof track.getCapabilities === "function" ? track.getCapabilities() : {};
  if (!capabilities.torch) {
    throw new Error("이 기기는 플래시 제어를 지원하지 않습니다.");
  }
  await track.applyConstraints({ advanced: [{ torch: enabled }] });
}
