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

## APK 빌드 후 Android 폰에 설치하기

앱을 Android 폰에 직접 설치하려면 Flutter/Android Studio 설정을 마친 뒤 APK 파일을 빌드해서 폰으로 옮기면 됩니다.

개발 테스트용 APK 빌드:

```bash
flutter build apk --debug
```

배포 확인용 APK 빌드:

```bash
flutter build apk --release
```

빌드된 APK 파일 위치:

```text
build/app/outputs/flutter-apk/app-debug.apk
build/app/outputs/flutter-apk/app-release.apk
```

Windows 기준 전체 경로 예시:

```text
C:\Users\PC\Desktop\find_cctv\find_cctv\build\app\outputs\flutter-apk\app-debug.apk
C:\Users\PC\Desktop\find_cctv\find_cctv\build\app\outputs\flutter-apk\app-release.apk
```

폰으로 옮기는 방법:

1. USB 케이블로 Android 폰을 PC에 연결합니다.
2. 폰 알림창의 USB 옵션에서 `파일 전송` 또는 `MTP`를 선택합니다.
3. Windows 파일 탐색기에서 폰의 `Download` 폴더를 엽니다.
4. 빌드된 APK 파일을 `Download` 폴더로 복사합니다.
5. 폰의 파일 관리자 앱에서 APK 파일을 터치해 설치합니다.
6. `알 수 없는 앱 설치 허용` 안내가 뜨면 해당 파일 관리자 앱에 설치 권한을 허용합니다.

앱을 수정한 뒤 업데이트하려면 APK를 다시 빌드한 다음 새 APK를 폰으로 다시 옮겨 설치해야 합니다. 같은 PC에서 같은 빌드 방식으로 만든 APK는 보통 기존 앱 위에 업데이트 설치됩니다.

설치가 되지 않을 때 확인할 것:

- 기존에 설치된 SafeLens 앱이 있으면 삭제 후 다시 설치합니다.
- 테스트 목적이면 `app-release.apk`보다 `app-debug.apk` 설치를 먼저 시도합니다.
- 폰의 Android 버전이 Android 7.0 이상인지 확인합니다. 이 앱의 최소 SDK는 24입니다.
- APK를 연 파일 관리자 또는 브라우저에 `알 수 없는 앱 설치` 권한이 허용되어 있는지 확인합니다.
