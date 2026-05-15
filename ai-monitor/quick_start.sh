#!/bin/bash

# Quick Start - Xcode 프로젝트 자동 생성 및 설정
# 사용법: ./quick_start.sh

set -e

PROJECT_NAME="AINewsWatch"
BUNDLE_ID="com.ainews.watch"
DEPLOYMENT_TARGET="17.0"

echo "🚀 AI News Watch - Quick Start"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Xcode 확인
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Xcode가 설치되어 있지 않습니다."
    echo ""
    echo "App Store에서 Xcode를 설치한 후 다시 실행하세요."
    exit 1
fi

echo "✓ Xcode 설치 확인됨"
echo ""

# 프로젝트 디렉토리 생성
PROJECT_DIR="${PROJECT_NAME}"
if [ -d "$PROJECT_DIR" ]; then
    echo "⚠️  프로젝트 디렉토리가 이미 존재합니다: $PROJECT_DIR"
    read -p "덮어쓰시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "취소되었습니다."
        exit 0
    fi
    rm -rf "$PROJECT_DIR"
fi

mkdir -p "$PROJECT_DIR"

echo "📁 프로젝트 디렉토리 생성: $PROJECT_DIR"
echo ""

# 소스 파일 복사
echo "📄 소스 파일 복사 중..."
cp AINewsWatchApp.swift "$PROJECT_DIR/"
cp ContentView.swift "$PROJECT_DIR/"
cp NewsCard.swift "$PROJECT_DIR/"
cp NewsMonitor.swift "$PROJECT_DIR/"
cp NewsCollector.swift "$PROJECT_DIR/"
cp SettingsView.swift "$PROJECT_DIR/"
cp Info.plist "$PROJECT_DIR/" 2>/dev/null || echo "  (Info.plist 스킵)"

echo "✓ 소스 파일 복사 완료"
echo ""

# 안내 메시지
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 파일 준비 완료!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "다음 단계:"
echo ""
echo "1️⃣  Xcode에서 새 프로젝트 생성"
echo "   - File > New > Project"
echo "   - iOS > App 선택"
echo "   - Product Name: $PROJECT_NAME"
echo "   - Interface: SwiftUI"
echo "   - Language: Swift"
echo ""
echo "2️⃣  생성된 프로젝트에 파일 추가"
echo "   - $PROJECT_DIR 폴더의 모든 .swift 파일을"
echo "   - Xcode 프로젝트로 드래그 앤 드롭"
echo ""
echo "3️⃣  Capabilities 설정"
echo "   - Target > Signing & Capabilities"
echo "   - + Capability > Background Modes 추가"
echo "   - Background fetch & processing 체크"
echo ""
echo "4️⃣  Info.plist 설정"
echo "   - Target > Info 탭"
echo "   - Permitted background task scheduler identifiers 추가"
echo "   - Item: com.ainews.refresh"
echo ""
echo "5️⃣  실행!"
echo "   - 시뮬레이터 선택 (iPhone 15 Pro)"
echo "   - Cmd+R로 빌드 및 실행"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "자세한 가이드: SETUP_GUIDE.md 참고"
echo ""

# 선택: Xcode 프로젝트 자동 생성 시도
read -p "Xcode 프로젝트를 자동으로 생성하시겠습니까? (실험적 기능) (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "🔨 Xcode 프로젝트 생성 중..."
    
    # xcodeproj 생성 (swift package 이용)
    cd "$PROJECT_DIR"
    
    # Package.swift 생성
    cat > Package.swift <<EOF
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "$PROJECT_NAME",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "$PROJECT_NAME", targets: ["$PROJECT_NAME"])
    ],
    targets: [
        .target(name: "$PROJECT_NAME", path: ".")
    ]
)
EOF

    echo "✓ Package.swift 생성"
    
    # Xcode 프로젝트 생성
    swift package generate-xcodeproj 2>/dev/null || {
        echo ""
        echo "⚠️  자동 생성에 실패했습니다."
        echo "   수동으로 Xcode에서 프로젝트를 생성해주세요."
        echo ""
        exit 0
    }
    
    cd ..
    
    echo "✓ Xcode 프로젝트 생성 완료"
    echo ""
    
    # Xcode에서 열기
    if [ -f "$PROJECT_DIR/$PROJECT_NAME.xcodeproj/project.pbxproj" ]; then
        echo "🎉 프로젝트를 Xcode에서 여는 중..."
        open "$PROJECT_DIR/$PROJECT_NAME.xcodeproj"
        echo ""
        echo "✅ 완료! Xcode에서 Cmd+R로 실행하세요."
    fi
else
    echo ""
    echo "수동 설정을 진행하세요."
    echo "SETUP_GUIDE.md를 참고하세요."
fi

echo ""
