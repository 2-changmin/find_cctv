# SafeLens

몰래카메라 의심 위치 탐지 보조와 신고 문안 생성을 위한 iOS 중심 모바일 앱 프로젝트입니다. React/Vite로 화면과 분석 로직을 만들고, Capacitor로 iOS/Android 네이티브 앱 형태로 실행합니다.

이 앱은 몰래카메라 존재를 확정 판정하지 않습니다. 사진과 카메라 화면에서 렌즈 반사처럼 보이는 후보를 찾아 사용자가 추가 확인하거나 신고 문안을 작성할 수 있도록 돕는 보조 도구입니다.

## 현재 구현된 기능

- 홈 화면
  - 사진 분석, 실시간 스캔, 신고 보조로 빠르게 이동
  - iPhone safe-area 지원으로 상태바/홈 인디케이터와 충돌 방지
  - 앱 스타일 중심의 파스텔 UI 적용

- 사진 분석
  - 사진 선택 또는 카메라 촬영으로 이미지 불러오기
  - 이미지 내 밝은 반사점/어두운 렌즈 코어 후보 탐지
  - 탐지 후보에 박스 표시 및 결과 카드 제공
  - 위험도 `높음 / 주의 / 낮음`과 confidence 퍼센트 표시
  - 분석 결과 이미지 별도 저장 지원

- 실시간 렌즈 반사 확인
  - iPhone 후면 카메라 스트림 분석
  - 프레임 누적 필터로 후보 깜빡임 완화
  - 위험도별 색상 표시
  - 플래시 토글 시도

- 고급 탐지 설정
  - 탐지 민감도 `낮음 / 보통 / 높음` 선택
  - 최소 탐지 신뢰도 설정으로 낮은 신뢰도 후보 자동 제외

- 신고 보조
  - 발견 일시, 장소, 의심 정황 입력
  - 현재 시간 자동 입력
  - 현 위치 좌표 자동 입력 및 주소 변환
  - 신고 문안 자동 생성
  - 분석 결과를 포함한 신고 리포트 ZIP 저장
  - 현재 분석 이미지 또는 실시간 스캔 캡처 자동 첨부
  - 분석 후보 목록과 박스 좌표 자동 포함
  - 위치 권한 거부 시 설정 화면 이동 버튼 제공
  - `112` 전화 연결 버튼

## 오늘 진행한 주요 변경 사항

- 기존 Android 중심 Capacitor 프로젝트에 iOS 타깃 추가
- Xcode에서 iPhone 실기기 설치 가능하도록 iOS 프로젝트 구성
- iOS 카메라/사진/위치 권한 문구 추가
- 사진 선택/촬영이 iPhone에서 정상 동작하도록 WebView 파일 입력 방식으로 수정
- 앱 상단이 iPhone 상태바를 침범하지 않도록 safe-area 여백 보정
- 전체 UI를 앱처럼 보이도록 홈 화면, 탭바, 결과 카드, 파스텔 테마로 개선
- 탐지 알고리즘을 분리하고 오탐 완화를 위해 원형성, 채움 비율, 주변 대비, 색 포화도, 가장자리 패널티 반영
- 분석 결과에 위험도와 confidence 표시 추가
- 실시간 스캔 결과도 위험도 색상으로 표시
- 신고 보조에 현재 시간/위치 자동 입력 기능 추가
- GitHub 업로드용 `.gitignore`, 문서, 개인정보 처리 초안 정리

## 기술 스택

- React 18
- Vite
- Capacitor 8
- iOS: Xcode 프로젝트
- Android: Android Studio 프로젝트
- Bootstrap 5

## 프로젝트 구조

```text
.
├── src/
│   ├── App.jsx              # 주요 화면과 앱 상태
│   ├── main.jsx             # React 진입점
│   ├── styles.css           # 전체 UI 스타일
│   └── lib/
│       ├── detector.js      # 의심 후보 탐지 알고리즘
│       ├── geocode.js       # 위치 주소 변환 유틸
│       ├── media.js         # 카메라/사진/파일 입력 관련 유틸
│       └── report.js        # 신고 문안 생성/저장 유틸
├── public/
│   └── app-icon.png
├── ios/                     # Capacitor iOS 네이티브 프로젝트
├── android/                 # Capacitor Android 네이티브 프로젝트
├── docs/
│   └── ios-release.md       # iOS 배포/TestFlight 관련 메모
├── PRIVACY.md               # 개인정보 처리 설명 초안
├── capacitor.config.json
├── package-lock.json
├── package.json
└── vite.config.js
```

`node_modules/`와 `dist/`는 GitHub에 올리지 않습니다. 다른 팀원은 `npm install`과 `npm run build`로 다시 생성하면 됩니다.

## GitHub 업로드 전 확인

GitHub에는 소스와 네이티브 프로젝트 설정만 올립니다. 아래 항목은 `.gitignore`로 제외됩니다.

- `node_modules/`
- `dist/`
- Android/iOS 빌드 산출물
- Capacitor가 네이티브 프로젝트 안에 복사한 웹 번들
- Xcode 사용자별 상태 파일
- `.env` 같은 로컬 환경 파일

새 저장소에 처음 올릴 때 예시:

```bash
git init
git add .
git commit -m "Initial SafeLens iOS app"
git branch -M main
git remote add origin <YOUR_GITHUB_REPO_URL>
git push -u origin main
```

팀원이 GitHub에서 받은 뒤 실행할 때:

```bash
git clone <YOUR_GITHUB_REPO_URL>
cd find_cctv-develop
npm install
npm run build
npm run cap:sync:ios
npm run cap:open:ios
```

## 개발 환경 준비

필수:

- Node.js
- npm
- macOS
- Xcode 26.3 이상 권장
- iPhone 실기기 테스트 시 iOS Developer Mode 활성화 필요

설치:

```bash
npm install
```

웹 개발 서버:

```bash
npm run dev
```

프로덕션 웹 빌드:

```bash
npm run build
```

## 개인 iPhone에 설치해서 실행하는 방법

이 방식은 발표용 팀원 기기에 직접 설치해 보여주는 방법입니다. TestFlight나 App Store 배포가 아니므로 Apple Developer Program 유료 계정 없이도 개인 테스트는 가능합니다.

1. Xcode 설치
2. 터미널에서 Xcode 경로 설정

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

3. 프로젝트 준비

```bash
npm install
npm run build
npm run cap:sync:ios
npm run cap:open:ios
```

4. Xcode에서 설정
   - 왼쪽 프로젝트에서 `App` 선택
   - `TARGETS > App` 선택
   - `Signing & Capabilities` 탭 이동
   - `Automatically manage signing` 체크
   - `Team`에서 본인 Apple ID 또는 Personal Team 선택
   - `Bundle Identifier`를 고유한 값으로 변경
     - 예: `com.yourname.safelens`

5. iPhone 연결
   - iPhone을 Mac에 USB로 연결
   - iPhone에서 `이 컴퓨터를 신뢰` 선택
   - Xcode 상단 실행 대상에서 연결된 iPhone 선택

6. iPhone Developer Mode 활성화
   - iPhone `설정 > 개인정보 보호 및 보안 > 개발자 모드`
   - 개발자 모드 켜기
   - iPhone 재시동
   - 재시동 후 개발자 모드 확인 창에서 켜기

7. Xcode에서 실행
   - 상단 ▶ Run 클릭
   - iPhone에 SafeLens 앱 설치 및 실행
   - 처음 사용하는 기능에서 카메라/사진/위치 권한 허용

참고:

- 무료 Apple ID로 설치한 앱은 일정 기간 후 만료될 수 있습니다.
- 발표 전날 또는 당일에 팀원 iPhone에 다시 설치해두는 것이 안전합니다.
- 여러 명이 QR로 직접 설치하는 TestFlight 배포는 Apple Developer Program 유료 계정이 필요합니다.

## iOS 실행 명령 요약

```bash
npm run build
npm run cap:sync:ios
npm run cap:open:ios
```

또는:

```bash
npm run ios
```

## Android 실행

Android 실행도 유지되어 있습니다.

```bash
npm run build
npm run cap:sync:android
npm run cap:open:android
```

또는:

```bash
npm run android
```

## 권한 설정

iOS 권한 문구는 `ios/App/App/Info.plist`에 들어 있습니다.

- `NSCameraUsageDescription`: 실시간 렌즈 반사 확인 및 촬영
- `NSPhotoLibraryUsageDescription`: 사진 선택 분석
- `NSLocationWhenInUseUsageDescription`: 신고 문안에 현재 위치 자동 입력

권한이 꼬였을 때는 iPhone에서 앱을 삭제한 뒤 Xcode로 다시 설치하거나, `설정 > 앱 > SafeLens`에서 권한을 다시 확인하세요.

## 현재 한계

- 탐지는 실제 AI 모델이 아니라 이미지 픽셀 기반 휴리스틱 분석에 의존합니다.
- 밝은 조명, 거울·금속 반사, 유리와 화면 가장자리에서 오탐이 발생할 수 있습니다.
- 실시간 스캔은 650ms 간격으로 프레임을 처리하므로 고속 움직임에서는 후보가 깜빡일 수 있습니다.
- iOS WebView에서 플래시/토치 제어 동작이 제한적일 수 있습니다.
- 위치 자동 입력은 네트워크 상태에 따라 주소 변환이 실패할 수 있으며, 이때 위도/경도 위주로 표시됩니다.
- 현재 분석 기록을 영구 저장하거나 과거 결과를 불러오는 기능은 없습니다.
- 모바일 앱 배포는 아직 TestFlight/App Store 절차를 거쳐야 합니다.

## 다음 개선 후보

- 탐지 민감도와 최소 신뢰도 값을 더 직관적으로 제어하는 UI 개선
- 권한 거부 시 설정 이동 버튼과 권한 재요청 플로우 개선
- 주소 변환/역지오코딩 안정성 향상 및 캐시 처리
- 분석 기록/히스토리 저장, 이전 결과 조회 기능 추가
- 이메일·메시지·카카오톡 공유 또는 신고 리포트 전송 기능
- 실제 머신러닝 기반 탐지 모델로 정확도 개선
- 다크 모드, 다국어 지원, 접근성 개선
