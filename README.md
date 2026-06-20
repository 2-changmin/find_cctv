# SafeLens

몰래카메라 의심 위치 탐지 보조와 신고 문안 생성을 위한 iOS 중심 모바일 앱 프로젝트입니다. React/Vite로 화면과 분석 로직을 만들고, Capacitor로 iOS/Android 네이티브 앱 형태로 실행합니다.

이 앱은 몰래카메라 존재를 확정 판정하지 않습니다. 사진과 카메라 화면에서 렌즈, 렌즈 반사, 유리 표면처럼 보이는 의심 후보를 찾아 사용자가 추가 확인하거나 신고 문안을 작성할 수 있도록 돕는 보조 도구입니다.

## 현재 구현된 기능

- 홈 화면
  - 사진 분석, 실시간 스캔, 신고 보조로 빠르게 이동
  - iPhone safe-area 지원으로 상태바/홈 인디케이터와 충돌 방지
  - 앱 스타일 중심의 파스텔 UI 적용

- 사진 분석
  - 사진 선택 또는 카메라 촬영으로 이미지 불러오기
  - 이미지 내 어두운 렌즈 코어, 밝은 렌즈 반사, 유리/코팅 반사 후보 탐지
  - 탐지 후보에 박스 표시 및 결과 카드 제공
  - 위험도 `높음 / 주의 / 낮음`과 confidence 퍼센트 표시

- 실시간 스캔
  - iPhone 후면 카메라 스트림 분석
  - 프레임 누적 필터로 후보 깜빡임 완화
  - 실시간 프레임에서는 완화된 탐지 기준을 적용하고, 같은 위치에서 반복 확인된 후보만 표시
  - 위험도별 색상 표시
  - 플래시 토글 시도

- 분석 기록
  - 최근 분석 결과를 로컬에 저장
  - 저장된 사진 분석 또는 실시간 스캔 결과 다시 불러오기

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

## 최신 탐지 알고리즘 정리

현재 탐지 로직은 `src/lib/detector.js`에 있으며, 단일 임계값으로 밝은 점만 찾는 방식이 아니라 2단계 후보 검증 방식으로 동작합니다.

이번 개선은 첨부 연구 요약의 대표 논문 중 **LAPD**의 광학 탐지 파이프라인을 현재 앱 구조에 맞게 반영했습니다. LAPD는 스마트폰 ToF/광원 반사 강도로 렌즈의 retroreflection 후보를 만든 뒤 물리 기반 필터와 ML 필터로 오탐을 줄이는 방식입니다. 이 프로젝트는 브라우저/Capacitor 기반이라 ToF intensity map, Wi-Fi CSI, 패킷 캡처, 열영상 센서를 직접 쓰지 못하므로, 배포 가능성이 높은 **RGB 카메라 프레임 + 플래시/조명 반사 + 프레임 간 밝기 증분**에 집중했습니다.

사용한 방식:

- LAPD식 광학 후보 검증
  - 렌즈가 만드는 작고 집중된 역반사점을 찾기 위해 원형성, 크기, 주변 대비, 중심부 하이라이트 집중도를 점수화합니다.
  - 밝은 점 하나만 보지 않고 어두운 렌즈 코어와 가까운 밝은 반사/유리면 후보가 함께 있는지 확인합니다.
- 자동 플래시 OFF/ON 차분 분석
  - 실시간 스캔에서 플래시 제어가 지원되면 `플래시 OFF 기준 프레임`을 먼저 저장하고, 다음 tick의 `플래시 ON 반사 프레임`과 비교합니다.
  - 전체 화면의 자동노출 변화량을 제거한 뒤 후보 주변에서만 밝기가 국소적으로 증가하는지 확인합니다.
  - 플래시 제어가 실패하거나 지원되지 않는 기기에서는 기존 연속 프레임 차분으로 자동 전환합니다.
- 시간적 안정성 필터
  - SCamF/CSI:DeSpy처럼 “한 순간의 신호”보다 반복 확인되는 신호를 더 신뢰하는 아이디어를 실시간 후보 누적에 적용했습니다.
  - 같은 위치와 비슷한 크기의 후보가 여러 프레임에서 반복될 때만 화면에 표시합니다.
- 교차검증형 evidence gate
  - 단일 특징만으로 후보를 통과시키지 않고 `형태`, `방사 대칭성`, `주변 대비`, `역반사`, `어두운 코어`, `보조 반사 후보`를 독립 근거로 계산합니다.
  - 민감도 `보통/낮음`에서는 최소 3개 근거, `높음`에서는 최소 2개 근거가 맞아야 후보로 유지합니다.
  - 강한 역반사 또는 어두운 코어+대비 조합처럼 렌즈 물리 특성이 뚜렷한 경우만 예외적으로 통과시킵니다.
  - 실시간 스캔에서는 여러 프레임에서 반복 확인된 비율을 persistence evidence로 최종 신뢰도에 반영합니다.

1차 후보 생성:

- 어두운 렌즈 후보
  - 주변보다 상대적으로 어두운 원형/타원형 영역
  - 검은 렌즈뿐 아니라 플래시 때문에 회색으로 보이는 렌즈도 일부 포함
- 밝은 반사 후보
  - 플래시나 조명을 받아 밝게 튀는 렌즈 반사 후보
- 유리/코팅 반사 후보
  - 렌즈 코팅이나 유리면처럼 중간톤 또는 색이 있는 반사 후보

2차 후보 검증:

- 후보의 원형/타원형 형태 점수
- 후보의 방사 대칭성 점수
- 후보 크기 점수
- 중심부와 주변 링의 밝기 대비
- 밝은 하이라이트 존재 여부
- 어두운 코어 존재 여부
- 근처에 보조 후보가 함께 있는지 여부
- 독립 근거 개수 기반 교차검증 통과 여부
- 줄눈, 나사 홈, 환풍구처럼 반복되거나 직선적인 패턴 감점
- 화면 가장자리 후보 감점
- 중심 하이라이트가 주변보다 작고 집중되어 있는지 확인
- 실시간 스캔에서는 플래시 OFF/ON 프레임 차분으로 후보 주변의 반사 증분 확인
- 플래시 미지원 기기에서는 연속 프레임 차분으로 fallback
- 전체 화면 자동노출 변화량을 제거한 뒤 국소 밝기 증분만 사용

결과 표시:

- 점수 기반으로 `높음 / 주의 / 낮음` 위험도를 표시합니다.
- confidence는 확률값이 아니라 렌즈 후보 특징을 얼마나 만족했는지 나타내는 내부 점수입니다.
- 민감도별 최대 표시 후보 수:
  - 낮음: 최대 3개
  - 보통: 최대 4개
  - 높음: 최대 5개

권장 테스트 설정:

- 실제 렌즈를 놓치는지 확인할 때: 민감도 `높음`, 최소 탐지 신뢰도 `20~30`
- 오탐을 줄이고 싶을 때: 민감도 `보통`, 최소 탐지 신뢰도 `40~50`
- 실시간 스캔은 손떨림과 자동 노출 영향을 받으므로 천천히 움직이며 같은 위치를 1~2초 정도 비추는 방식이 좋습니다.
- 플래시를 지원하는 기기에서는 앱이 자동으로 OFF/ON 차분을 반복하므로 같은 위치를 2~3초 정도 안정적으로 비추는 것이 좋습니다.
- 정확도가 낮게 느껴질 때는 먼저 `보통 / 최소 신뢰도 35~45`로 테스트하고, 실제 렌즈를 놓치면 `높음 / 25~35`로 낮춰 비교하세요.

한계:

- LAPD의 핵심 입력인 ToF intensity map은 아직 이 앱에서 사용하지 않습니다.
- DeWiCam, SCamF, CSI:DeSpy, LocCams 계열의 Wi-Fi 패킷/CSI 분석은 iOS/Android 배포 정책과 브라우저 권한 제약 때문에 현재 구현 범위에서 제외했습니다.
- HeatDeCam 계열의 열영상 탐지는 외부 열화상 센서가 필요하므로 일반 휴대폰 카메라만 쓰는 현재 앱에는 넣지 않았습니다.
- 따라서 결과는 몰래카메라 확정 판정이 아니라 “광학적으로 렌즈일 가능성이 있는 후보 표시”입니다.

## 최근 개선 사항

- 빨간 셀로판/빨간 필터 형태의 실시간 화면 효과 제거
- 렌즈 반사만 보는 방식에서 렌즈 자체 후보 검증 방식으로 전환
- 실제 렌즈가 빛을 받아 검정이 아닌 밝은색/회색/코팅 반사로 보이는 경우도 탐지하도록 후보군 확장
- 후보 크기 범위를 넓혀 가까이 촬영된 렌즈도 분석 가능하도록 개선
- 오탐 완화를 위해 줄눈, 나사 홈, 반복 구멍, 가장자리 후보 감점 적용
- 실시간 탐지는 사진 분석과 같은 기본 알고리즘을 사용하되 `liveMode`로 기준을 일부 완화
- `npm run build`, `npm run cap:sync:ios`, Xcode iOS Debug 빌드 확인

## 검증 상태

현재 코드 기준으로 확인한 명령:

```bash
npm run build
npm run cap:sync:ios
xcodebuild -project ios/App/App.xcodeproj -scheme App -configuration Debug -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build
```

위 명령은 모두 성공했습니다. 단, 실제 iPhone 설치는 Xcode `Signing & Capabilities`에서 Team과 Bundle Identifier가 올바르게 설정되어 있어야 합니다.

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
- 실시간 스캔은 500ms 간격으로 프레임을 처리하며, 빠르게 움직이면 후보 안정도가 떨어질 수 있습니다.
- iOS WebView에서 플래시/토치 제어 동작이 제한적일 수 있습니다.
- 위치 자동 입력은 네트워크 상태에 따라 주소 변환이 실패할 수 있으며, 이때 위도/경도 위주로 표시됩니다.
- 분석 기록은 로컬 스토리지에 보관되지만, 브라우저/앱 저장소가 지워지면 복구되지 않습니다.
- 모바일 앱 배포는 아직 TestFlight/App Store 절차를 거쳐야 합니다.

## 다음 개선 후보

- 탐지 민감도와 최소 신뢰도 값을 더 직관적으로 제어하는 UI 개선
- 권한 거부 시 설정 이동 버튼과 권한 재요청 플로우 개선
- 주소 변환/역지오코딩 안정성 향상 및 캐시 처리
- 분석 기록/히스토리 저장, 이전 결과 조회 기능 추가
- 이메일·메시지·카카오톡 공유 또는 신고 리포트 전송 기능
- 실제 머신러닝 기반 탐지 모델로 정확도 개선
- 다크 모드, 다국어 지원, 접근성 개선
