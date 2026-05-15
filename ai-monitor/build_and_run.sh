#!/bin/bash

# AI News Watch - Build & Run Script

set -e

echo "🚀 AI News Watch iOS 앱 빌드"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 1. Swift 버전 확인
echo "📋 Swift 버전 확인..."
swift --version
echo ""

# 2. 데모 실행 (커맨드라인 버전)
echo "🧪 데모 실행 (커맨드라인 버전)..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ -f "demo.swift" ]; then
    chmod +x demo.swift
    swift demo.swift
    echo ""
else
    echo "⚠️  demo.swift 파일을 찾을 수 없습니다."
    echo ""
fi

# 3. Xcode 프로젝트가 있는 경우 iOS 시뮬레이터에서 실행
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📱 iOS 앱 빌드 및 실행"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if command -v xcodebuild &> /dev/null; then
    echo "✓ Xcode가 설치되어 있습니다."
    echo ""
    
    # Xcode 프로젝트 확인
    if [ -f "AINewsWatch.xcodeproj/project.pbxproj" ]; then
        echo "📦 Xcode 프로젝트 발견"
        echo ""
        
        # 시뮬레이터 목록
        echo "사용 가능한 시뮬레이터:"
        xcrun simctl list devices available | grep "iPhone"
        echo ""
        
        # 기본 시뮬레이터에서 빌드
        echo "🔨 빌드 중..."
        xcodebuild \
            -project AINewsWatch.xcodeproj \
            -scheme AINewsWatch \
            -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
            build
        
        echo ""
        echo "✅ 빌드 완료!"
        echo ""
        echo "실행하려면:"
        echo "  1. Xcode에서 AINewsWatch.xcodeproj 열기"
        echo "  2. 시뮬레이터 선택 (iPhone 15 Pro 등)"
        echo "  3. cmd+R로 실행"
        echo ""
        
    else
        echo "⚠️  Xcode 프로젝트를 찾을 수 없습니다."
        echo ""
        echo "Xcode에서 새 프로젝트를 생성하세요:"
        echo "  1. Xcode 실행"
        echo "  2. File > New > Project"
        echo "  3. iOS > App 선택"
        echo "  4. Product Name: AINewsWatch"
        echo "  5. Interface: SwiftUI, Language: Swift"
        echo "  6. 다음 파일들을 프로젝트에 추가:"
        echo "     - AINewsWatchApp.swift"
        echo "     - ContentView.swift"
        echo "     - NewsCard.swift"
        echo "     - NewsMonitor.swift"
        echo "     - NewsCollector.swift"
        echo "     - SettingsView.swift"
        echo ""
    fi
else
    echo "⚠️  Xcode가 설치되어 있지 않습니다."
    echo ""
    echo "macOS에서 Xcode를 설치하세요:"
    echo "  1. App Store에서 'Xcode' 검색"
    echo "  2. 다운로드 및 설치 (무료, 약 15GB)"
    echo "  3. 설치 후 이 스크립트 다시 실행"
    echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📖 참고 문서"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "자세한 사용법은 README.md를 참고하세요."
echo ""
echo "주요 파일:"
echo "  - AINewsWatchApp.swift : 앱 진입점"
echo "  - ContentView.swift    : 메인 UI"
echo "  - NewsMonitor.swift    : 상태 관리 + WiFi 감지"
echo "  - NewsCollector.swift  : 뉴스 수집 로직"
echo "  - demo.swift          : 커맨드라인 데모"
echo ""
echo "✅ 완료!"
