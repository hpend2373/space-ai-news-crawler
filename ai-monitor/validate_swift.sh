#!/bin/bash

# Swift 파일 문법 검증 스크립트
echo "🔍 Swift 코드 문법 검증 시작..."
echo ""

# swiftc가 있는지 확인
if ! command -v swiftc &> /dev/null; then
    echo "❌ Swift 컴파일러를 찾을 수 없습니다."
    echo "   Xcode Command Line Tools를 설치하세요:"
    echo "   xcode-select --install"
    exit 1
fi

echo "✅ Swift 컴파일러 발견: $(swiftc --version | head -n 1)"
echo ""

# 각 파일 검증
files=(
    "AINewsWatchApp.swift"
    "ContentView.swift"
    "NewsCard.swift"
    "NewsMonitor.swift"
    "NewsCollector.swift"
    "SettingsView.swift"
)

errors=0

for file in "${files[@]}"; do
    if [ ! -f "$file" ]; then
        echo "⚠️  $file - 파일 없음"
        continue
    fi
    
    echo -n "📄 $file ... "
    
    # 문법만 체크 (-typecheck)
    if swiftc -typecheck -target arm64-apple-ios17.0 -sdk $(xcrun --show-sdk-path --sdk iphoneos) "$file" 2>/dev/null; then
        echo "✅"
    else
        echo "❌"
        echo "   오류 상세:"
        swiftc -typecheck -target arm64-apple-ios17.0 -sdk $(xcrun --show-sdk-path --sdk iphoneos) "$file" 2>&1 | head -n 10
        errors=$((errors + 1))
    fi
done

echo ""
if [ $errors -eq 0 ]; then
    echo "🎉 모든 파일 문법 검증 통과!"
    echo ""
    echo "다음 단계:"
    echo "  1. Xcode에서 새 프로젝트 생성"
    echo "  2. 이 파일들을 프로젝트에 추가"
    echo "  3. ⌘ + R 로 실행"
else
    echo "⚠️  $errors 개 파일에 오류가 있습니다."
    echo "   위의 오류 메시지를 확인하세요."
fi
