# SafeLens App (Flutter)

몰래카메라 의심 지점 탐지 보조와 신고 보조를 위한 Android 앱 프로젝트입니다.

## 개발 실행

1. Flutter SDK 설치
2. 설치 후 PATH 등록
3. Android Studio 설치 후 `SDK Manager`에서 아래 항목 설치
   - Android SDK Platform
   - Android SDK Build-Tools
   - Android SDK Platform-Tools
   - Android Emulator
4. Flutter 환경 확인

```bash
flutter doctor -v
```

5. 프로젝트 의존성 설치

```bash
flutter pub get
```

6. 에뮬레이터 생성 또는 실행

```bash
flutter emulators
flutter emulators --launch <에뮬레이터_이름>
```

7. 앱 실행

```bash
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

## Git 줄바꿈 정책 (GeneratedPluginRegistrant)

`android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java` 파일은 Flutter가 자동 생성하는 파일입니다.
Windows 환경에서는 코드 내용이 같아도 줄바꿈 문자(CRLF/LF) 차이 때문에 변경된 것처럼 보일 수 있습니다.

이 저장소에는 Git에서 텍스트 파일 줄바꿈을 LF로 정규화하기 위한 `.gitattributes`가 포함되어 있습니다.

권장 1회 설정:

```bash
git config core.autocrlf true
git add --renormalize .
git status
```

재정규화 후 `git status`가 깨끗하면 실제 소스 변경은 없는 상태입니다.

