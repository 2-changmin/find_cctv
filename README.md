# SafeLens App (Flutter)

몰래카메라 의심 지점 탐지 보조와 신고 보조를 위한 Android 앱 프로젝트입니다.

## 개발 실행

1. Flutter SDK 설치 후 PATH 등록
2. VSCode에서 Flutter/Dart 확장 설치
3. Android 에뮬레이터 실행
4. 프로젝트 루트에서 실행

```bash
flutter pub get
flutter run
```

## 주요 구조

- `lib/main.dart` : Flutter 앱 화면, 이미지 분석, 카메라 확인, 신고 보조 로직
- `android/` : Flutter Android 래퍼 프로젝트
- `public/app-icon.png` : 앱 내부 아이콘 에셋
- `src/`, `package.json` : 이전 React/Capacitor 구현 소스

## 기능

- 이미지 선택 후 의심 지점 분석
- 카메라 프리뷰와 주기적 렌즈 반사 후보 표시
- 플래시 토글
- 신고 보조 문안 생성 및 텍스트 저장
- 112 전화 연결
- 서버 API, API 키, 인터넷 권한 없이 기기 로컬에서 동작

## 주의

- 이 앱은 몰래카메라 존재를 확정하지 않는 보조 도구입니다.
- 현재 분석은 머신러닝 모델이 아니라 밝기/대비 기반 로컬 휴리스틱입니다.
- 카메라/플래시 동작은 실제 기기와 에뮬레이터 환경에 따라 제한될 수 있습니다.
