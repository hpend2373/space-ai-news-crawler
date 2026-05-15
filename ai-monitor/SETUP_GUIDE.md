# Xcode 프로젝트 생성 및 실행 가이드

Python 스크립트를 iOS 앱으로 변환한 프로젝트입니다. 아래 단계를 따라 실행하세요.

## 방법 1: 커맨드라인 데모 (빠른 테스트)

macOS에서 Swift가 설치되어 있다면:

```bash
# 실행 권한 부여
chmod +x build_and_run.sh
chmod +x demo.swift

# 데모 실행
./demo.swift

# 또는 빌드 스크립트 실행
./build_and_run.sh
```

이 방법은 iOS 시뮬레이터 없이 핵심 로직만 테스트합니다.

## 방법 2: Xcode에서 전체 iOS 앱 빌드 및 실행 (권장)

### 1단계: Xcode 프로젝트 생성

1. **Xcode 실행**
2. **File > New > Project** (또는 `Cmd+Shift+N`)
3. **iOS** 탭 선택
4. **App** 템플릿 선택 → **Next**
5. 프로젝트 설정:
   - **Product Name**: `AINewsWatch`
   - **Team**: 본인 Apple ID
   - **Organization Identifier**: `com.yourname`
   - **Interface**: **SwiftUI**
   - **Language**: **Swift**
   - **Storage**: None (기본값)
   - **Include Tests**: 선택 해제 (선택사항)
6. **Next** → 저장 위치 선택 → **Create**

### 2단계: 기본 파일 삭제 및 교체

1. 왼쪽 **Project Navigator**에서 자동 생성된 파일들 확인
2. `ContentView.swift` 파일 **선택 후 삭제** (또는 덮어쓰기)
3. `AINewsWatchApp.swift` 파일 **선택 후 덮어쓰기**

### 3단계: 새 파일들 추가

1. **Project Navigator**에서 프로젝트 이름 우클릭
2. **Add Files to "AINewsWatch"...** 선택
3. 다음 파일들을 선택하여 추가:
   ```
   ✓ AINewsWatchApp.swift      (덮어쓰기)
   ✓ ContentView.swift          (덮어쓰기)
   ✓ NewsCard.swift             (새로 추가)
   ✓ NewsMonitor.swift          (새로 추가)
   ✓ NewsCollector.swift        (새로 추가)
   ✓ SettingsView.swift         (새로 추가)
   ```
4. **Options**에서 다음을 확인:
   - ✅ **Copy items if needed**
   - ✅ **Create groups**
   - ✅ **Add to targets: AINewsWatch**

### 4단계: Info.plist 설정

#### Option A: Info.plist 파일로 설정 (구버전 Xcode)

1. `Info.plist` 파일을 프로젝트에 추가
2. 제공된 `Info.plist` 내용 복사

#### Option B: Target 설정에서 직접 설정 (신버전 Xcode, 권장)

1. **Project Navigator**에서 프로젝트 최상위 아이콘 클릭
2. **TARGETS** 섹션에서 `AINewsWatch` 선택
3. **Signing & Capabilities** 탭

**Background Modes 추가:**
4. **+ Capability** 버튼 클릭
5. **Background Modes** 검색 후 추가
6. 다음 옵션 체크:
   - ✅ **Background fetch**
   - ✅ **Background processing**

**App Transport Security 설정:**
7. **Info** 탭으로 이동
8. 우클릭 → **Add Row**
9. Key: `App Transport Security Settings` (딕셔너리)
10. 하위에 다음 추가:
    - `Allow Arbitrary Loads`: `YES` (Boolean)
    
    > ⚠️ 프로덕션에서는 특정 도메인만 허용하는 것이 좋습니다

**Background Task Identifiers:**
11. 같은 **Info** 탭에서
12. 우클릭 → **Add Row**
13. Key: `Permitted background task scheduler identifiers` (Array)
14. Item 0: `com.ainews.refresh` (String)

### 5단계: 시뮬레이터 선택 및 실행

1. 상단 툴바에서 시뮬레이터 선택:
   - **iPhone 15 Pro** (권장)
   - 또는 다른 iPhone 모델

2. **Product > Run** (또는 `Cmd+R`)

3. 시뮬레이터 부팅 및 앱 설치

4. 앱 실행!

### 6단계: WiFi 시뮬레이션

시뮬레이터는 Mac의 네트워크를 공유하므로:
- Mac이 WiFi에 연결되어 있으면 → 앱이 "WiFi 연결됨" 표시
- 이더넷 연결이면 → "WiFi 없음" (자동 새로고침 안 됨)

#### WiFi 테스트하려면:
1. Mac을 WiFi에 연결
2. 앱 재시작
3. 상단에 "WiFi 연결됨" 확인
4. 새로고침 버튼 탭

### 7단계: 백그라운드 작업 테스트

시뮬레이터에서 백그라운드 작업을 강제 실행:

1. 앱 실행 중
2. **Xcode > Debug > Simulate Background Fetch** 메뉴 없음
3. 대신 lldb 명령어 사용:

```bash
# Xcode 하단 콘솔에서
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.ainews.refresh"]
```

## 방법 3: 실제 iPhone에서 실행

### 1. 개발자 계정 설정

1. **Xcode > Settings > Accounts**
2. **+ 버튼** → Apple ID 로그인
3. 무료 개인 팀 자동 생성

### 2. 서명 설정

1. **Target > Signing & Capabilities**
2. **Team** 드롭다운에서 본인 계정 선택
3. **Automatically manage signing** 체크

### 3. 기기 연결 및 신뢰

1. iPhone을 Lightning/USB-C 케이블로 Mac에 연결
2. iPhone에서 "이 컴퓨터를 신뢰하십니까?" → **신뢰**
3. Xcode 상단 툴바에서 연결된 iPhone 선택

### 4. 실행

1. **Product > Run** (`Cmd+R`)
2. iPhone에 앱 설치 및 실행
3. 첫 실행 시 "신뢰되지 않은 개발자" 경고:
   - **iPhone 설정 > 일반 > VPN 및 기기 관리**
   - 본인 Apple ID → **신뢰**
4. 앱 재실행

### 5. 실제 WiFi 테스트

1. iPhone을 WiFi에 연결
2. 앱 실행
3. "WiFi 연결됨" 상태 확인
4. 새로고침 버튼 탭하여 뉴스 수집

## 트러블슈팅

### 빌드 오류: "Cannot find type 'BGTaskScheduler'"

- **iOS Deployment Target**을 **17.0 이상**으로 설정:
  1. Target > General > Minimum Deployments
  2. iOS 17.0 선택

### 빌드 오류: "Module compiled with Swift X.X cannot be imported by Swift Y.Y"

- Xcode와 Swift 버전 불일치
- **Xcode > Settings > Locations**에서 Command Line Tools 확인

### 네트워크 오류: "The resource could not be loaded because the App Transport Security policy"

- Info.plist에 ATS 설정 추가 (위 4단계 참고)

### Nitter 파싱 실패: "파싱 실패 (0개)"

- Nitter 인스턴스가 다운되었거나 HTML 구조 변경
- `NewsMonitor.swift`의 `loadConfiguration()`에서 다른 인스턴스 시도:
  ```swift
  instances: [
      "https://nitter.poast.org",       // 기본
      "https://nitter.privacydev.net",  // 대체
      "https://nitter.net",             // 대체
      "https://nitter.cz",              // 추가
      "https://nitter.unixfox.eu"       // 추가
  ]
  ```

### 백그라운드 새로고침이 작동하지 않음

- iOS는 백그라운드 작업을 보장하지 않습니다
- 다음을 확인:
  1. **설정 > 일반 > 백그라운드 앱 새로고침** 활성화
  2. WiFi 연결 유지
  3. 저전력 모드 비활성화
  4. 앱을 자주 사용 (iOS가 학습)

### 데모 스크립트 실행 시 "Operation not permitted"

```bash
chmod +x demo.swift
chmod +x build_and_run.sh
./demo.swift
```

## 다음 단계

앱이 정상 작동하면:

1. **README.md** 읽고 기능 탐색
2. **설정**에서 시간 범위, 자동 새로고침 조정
3. **NewsMonitor.swift**에서 모니터링할 계정/RSS 추가
4. **번역 기능** 구현 (TODO)
5. **Widget** 추가
6. **TestFlight**로 배포

## 참고 자료

- [Apple Developer - Background Tasks](https://developer.apple.com/documentation/backgroundtasks)
- [SwiftUI Tutorials](https://developer.apple.com/tutorials/swiftui)
- [Nitter Project](https://github.com/zedeus/nitter)

---

문제가 발생하면 GitHub Issues에 보고해주세요!
