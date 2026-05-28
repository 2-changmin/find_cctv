# SafeLens iOS Release

이 프로젝트는 React/Vite 앱을 Capacitor로 감싼 iOS 앱입니다. 발표장에서 QR로 설치시키려면 앱 빌드 파일을 직접 QR에 넣는 것이 아니라 Apple이 허용하는 배포 링크를 QR로 변환해야 합니다.

## 권장 배포 방식

## macOS Sequoia 15.6.1에서 Xcode 설치

Mac App Store는 최신 Xcode만 보여줄 수 있고, 최신 Xcode가 macOS Tahoe 26.2 이상을 요구하면 Sequoia 15.6.1에서는 설치가 막힙니다.

이 경우 Apple Developer 다운로드 페이지에서 이전 호환 버전을 직접 받으세요.

- 권장: Xcode 26.3
- 이유: Apple 공식 Xcode 지원표 기준 Xcode 26.3은 macOS Sequoia 15.6 이상을 지원합니다.
- 다운로드 위치: https://developer.apple.com/download/all/
- 설치 후 `/Applications/Xcode.app`로 이동
- 최초 실행 후 추가 컴포넌트 설치
- 필요 시 터미널에서 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`

App Store Connect 제출에는 현재 Xcode 26 계열과 iOS 26 SDK가 필요하므로, Sequoia 15.6.1에서는 Xcode 26.3을 쓰는 것이 가장 현실적인 로컬 빌드 경로입니다.

### 1. TestFlight Public Link

발표장에서 불특정 다수 또는 여러 명이 직접 설치해야 한다면 이 방식을 사용합니다.

1. Apple Developer Program 가입 계정 준비
2. Xcode 설치
3. `npm install`
4. `npm run build`
5. `npm run cap:sync:ios`
6. `npm run cap:open:ios`
7. Xcode에서 Signing Team과 Bundle Identifier 설정
8. 실제 iPhone에서 카메라, 사진 선택, 신고 문안 기능 확인
9. Xcode Product > Archive
10. Distribute App > App Store Connect 업로드
11. App Store Connect에서 TestFlight 외부 테스트 제출
12. Beta App Review 승인 후 Public Link 생성
13. Public Link를 QR 코드로 변환

Apple 공식 문서상 TestFlight는 공개 링크 초대를 만들 수 있고, 설치와 피드백은 TestFlight 앱을 통해 진행됩니다.

## 대안 배포 방식

### Ad Hoc

설치할 iPhone의 UDID를 미리 수집해 Apple Developer 계정에 등록해야 합니다. 발표 당일 현장 참여자가 바뀌거나 기기가 많으면 운영이 어렵습니다.

### App Store

가장 안정적인 공개 배포 방식입니다. 다만 심사와 일정 여유가 필요합니다.

### Enterprise

Apple Developer Enterprise Program은 조직 내부 직원 대상 배포 용도입니다. 학교 발표나 일반 참가자 배포 목적으로 쓰면 안 됩니다.

## 로컬 빌드 명령

```bash
npm install
npm run build
npm run cap:sync:ios
npm run cap:open:ios
```

## Xcode 필수 설정

- Team: Apple Developer Program에 가입된 팀
- Bundle Identifier: 기본값 `com.safelens.app`; 실제 배포에서는 고유 값으로 변경
- Version: `1.0`
- Signing: Automatically manage signing 권장
- Camera permission: `NSCameraUsageDescription` 설정 완료
- Photo permission: `NSPhotoLibraryUsageDescription` 설정 완료

## 발표 전 체크리스트

- 실제 iPhone에서 사진 선택이 열리는지 확인
- 실제 iPhone에서 촬영 후 분석이 가능한지 확인
- 실시간 렌즈 반사 확인 시작 시 카메라 권한 팝업이 뜨는지 확인
- 플래시 버튼은 기기와 iOS WebView 지원 여부에 따라 비활성 또는 실패할 수 있음
- TestFlight 링크를 QR로 열었을 때 설치 흐름이 정상인지 확인
- 발표장 네트워크가 불안정할 수 있으므로 TestFlight 설치를 사전에 안내
