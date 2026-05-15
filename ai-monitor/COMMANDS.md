# AI News Watch - 명령어 모음

이 문서는 프로젝트에서 사용할 수 있는 모든 명령어를 정리한 것입니다.

## 기본 명령어

### 1. 데모 실행 (Swift CLI)

```bash
# 실행 권한 부여
chmod +x demo.swift

# 데모 실행
./demo.swift

# 또는
swift demo.swift
```

### 2. 빌드 스크립트 실행

```bash
chmod +x build_and_run.sh
./build_and_run.sh
```

### 3. Quick Start (자동 설정)

```bash
chmod +x quick_start.sh
./quick_start.sh
```

## Xcode 명령어

### 프로젝트 빌드 (커맨드라인)

```bash
# 시뮬레이터용 빌드
xcodebuild \
  -project AINewsWatch.xcodeproj \
  -scheme AINewsWatch \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  build

# 실제 기기용 빌드
xcodebuild \
  -project AINewsWatch.xcodeproj \
  -scheme AINewsWatch \
  -destination 'generic/platform=iOS' \
  build
```

### 시뮬레이터에서 실행

```bash
# 시뮬레이터 목록 확인
xcrun simctl list devices

# 특정 시뮬레이터 부팅
xcrun simctl boot "iPhone 15 Pro"

# 앱 설치 (빌드 후)
xcrun simctl install booted path/to/AINewsWatch.app

# 앱 실행
xcrun simctl launch booted com.ainews.watch
```

### 백그라운드 작업 테스트

Xcode에서 앱 실행 중 lldb 콘솔에 입력:

```lldb
# 백그라운드 새로고침 시뮬레이션
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.ainews.refresh"]
```

### 클린 빌드

```bash
# 빌드 캐시 삭제
rm -rf ~/Library/Developer/Xcode/DerivedData/AINewsWatch-*

# 또는 Xcode에서
# Product > Clean Build Folder (Shift+Cmd+K)
```

## 개발 명령어

### Swift 포맷팅

```bash
# swift-format 설치 (처음 한 번만)
brew install swift-format

# 모든 Swift 파일 포맷팅
swift-format -i -r *.swift

# 특정 파일만
swift-format -i ContentView.swift
```

### 코드 린팅

```bash
# SwiftLint 설치
brew install swiftlint

# 린팅 실행
swiftlint lint

# 자동 수정
swiftlint --fix
```

### 문법 체크

```bash
# 컴파일 없이 문법만 체크
swiftc -typecheck AINewsWatchApp.swift ContentView.swift NewsCard.swift NewsMonitor.swift NewsCollector.swift SettingsView.swift
```

## 디버깅 명령어

### 네트워크 디버깅

시뮬레이터에서 네트워크 요청 모니터링:

```bash
# 프록시 설정 (Charles Proxy 등 사용 시)
xcrun simctl spawn booted defaults write com.apple.CFNetwork ProxyHost "127.0.0.1"
xcrun simctl spawn booted defaults write com.apple.CFNetwork ProxyPort 8888
```

### 로그 확인

```bash
# 시뮬레이터 로그
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.ainews.watch"'

# 또는 Console.app에서 필터링:
# - 실행 중인 시뮬레이터 선택
# - "AINewsWatch" 검색
```

### 시뮬레이터 초기화

```bash
# 특정 시뮬레이터 초기화
xcrun simctl erase "iPhone 15 Pro"

# 모든 시뮬레이터 초기화
xcrun simctl erase all
```

## 배포 명령어

### Archive 생성

```bash
xcodebuild \
  -project AINewsWatch.xcodeproj \
  -scheme AINewsWatch \
  -archivePath ./build/AINewsWatch.xcarchive \
  archive
```

### IPA 파일 생성 (TestFlight/App Store)

```bash
xcodebuild \
  -exportArchive \
  -archivePath ./build/AINewsWatch.xcarchive \
  -exportPath ./build \
  -exportOptionsPlist ExportOptions.plist
```

## 유틸리티 명령어

### 파일 트리 확인

```bash
tree -L 2 -I 'node_modules|.git'
```

### Swift 버전 확인

```bash
swift --version
xcodebuild -version
```

### 설치된 시뮬레이터 목록

```bash
xcrun simctl list devices available | grep iPhone
```

### 앱 Bundle ID 확인

```bash
# Info.plist에서
/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" Info.plist

# 또는 빌드된 앱에서
codesign -d --entitlements - path/to/AINewsWatch.app
```

## Git 명령어 (버전 관리)

```bash
# 저장소 초기화
git init

# .gitignore 생성
cat > .gitignore <<EOF
# Xcode
*.xcodeproj/*
!*.xcodeproj/project.pbxproj
!*.xcworkspace/contents.xcworkspacedata
*.xcworkspace/*
!*.xcworkspace/contents.xcworkspacedata
DerivedData/
*.xcuserstate

# Swift
.build/
*.swiftpm
.DS_Store

# Python
__pycache__/
*.pyc
.cache/
reports/
logs/

# Config
config.json
EOF

# 커밋
git add .
git commit -m "Initial commit: iOS app for AI News Watch"
```

## 문제 해결 명령어

### Xcode 재설정

```bash
# Xcode 캐시 삭제
rm -rf ~/Library/Developer/Xcode/DerivedData
rm -rf ~/Library/Caches/com.apple.dt.Xcode

# Command Line Tools 재선택
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

### 시뮬레이터 재시작

```bash
# 모든 시뮬레이터 종료
xcrun simctl shutdown all

# 시뮬레이터 앱 재시작
killall "Simulator"
open /Applications/Xcode.app/Contents/Developer/Applications/Simulator.app
```

### 프로비저닝 프로파일 새로고침

```bash
# Xcode에서 자동으로 관리하는 경우
rm -rf ~/Library/MobileDevice/Provisioning\ Profiles

# Xcode 재시작 후 프로젝트 다시 열기
```

## Python 원본 스크립트 실행 (비교용)

```bash
# Python 스크립트 실행
python3 ai_agent.py run --hours 24

# 헬스체크
python3 ai_agent.py health
```

## 통합 워크플로우

### 개발 → 테스트 → 빌드

```bash
#!/bin/bash

# 1. 포맷 및 린트
swift-format -i -r *.swift
swiftlint --fix

# 2. 문법 체크
swiftc -typecheck *.swift

# 3. 데모 실행 (로직 테스트)
swift demo.swift

# 4. Xcode 빌드
xcodebuild -project AINewsWatch.xcodeproj -scheme AINewsWatch -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build

# 5. 시뮬레이터에서 실행
open -a Simulator
xcrun simctl launch booted com.ainews.watch
```

## 성능 프로파일링

### Instruments로 프로파일링

```bash
# 타임 프로파일러
instruments -t "Time Profiler" -D ~/Desktop/profile.trace path/to/AINewsWatch.app

# 메모리 프로파일러
instruments -t "Allocations" -D ~/Desktop/memory.trace path/to/AINewsWatch.app

# 네트워크 프로파일러
instruments -t "Network" -D ~/Desktop/network.trace path/to/AINewsWatch.app
```

---

## 단축 명령어 모음 (alias 추가)

`.zshrc` 또는 `.bashrc`에 추가:

```bash
# AI News Watch 단축 명령어
alias anw-demo='swift demo.swift'
alias anw-build='./build_and_run.sh'
alias anw-clean='rm -rf ~/Library/Developer/Xcode/DerivedData/AINewsWatch-*'
alias anw-sim='xcrun simctl launch booted com.ainews.watch'
alias anw-logs='xcrun simctl spawn booted log stream --predicate "subsystem == \"com.ainews.watch\""'
```

적용:

```bash
source ~/.zshrc  # 또는 source ~/.bashrc
```

사용:

```bash
anw-demo    # 데모 실행
anw-build   # 빌드
anw-sim     # 시뮬레이터에서 앱 실행
anw-logs    # 로그 확인
```

---

**모든 명령어는 프로젝트 루트 디렉토리에서 실행해야 합니다.**
