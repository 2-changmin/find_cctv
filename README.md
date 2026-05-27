# SafeLens App (React + Capacitor)

몰래카메라 의심 지점 탐지 보조와 신고 보조를 위한 Android 앱 프로젝트입니다.

## 개발(웹)
1. `npm install`
2. `npm run dev`

## Android 앱 실행
1. `npm run build`
2. `npx cap sync android`
3. `npx cap open android`
4. Android Studio에서 에뮬레이터 선택 후 `Run`(▶)

또는 한 번에:
- `npm run android`

## 구조
- `src/` : React 앱 소스
- `dist/` : 웹 빌드 산출물
- `android/` : Android 네이티브 프로젝트

## 주의
- 이 앱은 몰래카메라 존재를 확정하지 않는 보조 도구입니다.
- 카메라/플래시 동작은 기기 및 Android 에뮬레이터 환경에 따라 제한될 수 있습니다.
