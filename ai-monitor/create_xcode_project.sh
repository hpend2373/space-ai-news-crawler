#!/bin/bash

# AI News Watch - 프로젝트 자동 생성 및 빌드 스크립트
# 사용법: chmod +x create_xcode_project.sh && ./create_xcode_project.sh

set -e

PROJECT_NAME="AINewsWatch"
BUNDLE_ID="com.ainews.watch"
PROJECT_DIR="$HOME/Desktop/$PROJECT_NAME"

echo "🚀 AI News Watch 프로젝트 생성 시작..."
echo ""

# 1. 프로젝트 디렉토리 생성
echo "📁 프로젝트 디렉토리 생성: $PROJECT_DIR"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/$PROJECT_NAME"

# 2. Swift 파일들 복사
echo "📄 Swift 파일 복사 중..."
cp -f AINewsWatchApp.swift "$PROJECT_DIR/$PROJECT_NAME/"
cp -f ContentView.swift "$PROJECT_DIR/$PROJECT_NAME/"
cp -f NewsCard.swift "$PROJECT_DIR/$PROJECT_NAME/"
cp -f NewsMonitor.swift "$PROJECT_DIR/$PROJECT_NAME/"
cp -f NewsCollector.swift "$PROJECT_DIR/$PROJECT_NAME/"
cp -f SettingsView.swift "$PROJECT_DIR/$PROJECT_NAME/"

# 3. Assets 디렉토리 생성
echo "🎨 Assets 생성 중..."
mkdir -p "$PROJECT_DIR/$PROJECT_NAME/Assets.xcassets/AppIcon.appiconset"
cat > "$PROJECT_DIR/$PROJECT_NAME/Assets.xcassets/AppIcon.appiconset/Contents.json" << 'EOF'
{
  "images" : [
    {
      "filename" : "icon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

mkdir -p "$PROJECT_DIR/$PROJECT_NAME/Assets.xcassets/AccentColor.colorset"
cat > "$PROJECT_DIR/$PROJECT_NAME/Assets.xcassets/AccentColor.colorset/Contents.json" << 'EOF'
{
  "colors" : [
    {
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

cat > "$PROJECT_DIR/$PROJECT_NAME/Assets.xcassets/Contents.json" << 'EOF'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

# 4. Info.plist 생성
echo "⚙️  Info.plist 생성 중..."
cat > "$PROJECT_DIR/$PROJECT_NAME/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>UIBackgroundModes</key>
	<array>
		<string>fetch</string>
		<string>processing</string>
	</array>
	<key>BGTaskSchedulerPermittedIdentifiers</key>
	<array>
		<string>com.ainews.refresh</string>
	</array>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoads</key>
		<true/>
	</dict>
</dict>
</plist>
EOF

# 5. project.pbxproj 생성
echo "🔧 Xcode 프로젝트 파일 생성 중..."
cat > "$PROJECT_DIR/$PROJECT_NAME.xcodeproj/project.pbxproj" << 'PBXPROJ'
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {
		A1000001000000000000001 /* AINewsWatch */ = {
			isa = PBXGroup;
			children = (
				A1000002000000000000002 /* AINewsWatchApp.swift */,
				A1000003000000000000003 /* ContentView.swift */,
				A1000004000000000000004 /* NewsCard.swift */,
				A1000005000000000000005 /* NewsMonitor.swift */,
				A1000006000000000000006 /* NewsCollector.swift */,
				A1000007000000000000007 /* SettingsView.swift */,
				A1000008000000000000008 /* Assets.xcassets */,
				A1000009000000000000009 /* Info.plist */,
			);
			path = AINewsWatch;
			sourceTree = "<group>";
		};
		A100000A00000000000000A /* Products */ = {
			isa = PBXGroup;
			children = (
				A100000B00000000000000B /* AINewsWatch.app */,
			);
			name = Products;
			sourceTree = "<group>";
		};
	};
	rootObject = A100000C00000000000000C /* Project object */;
}
PBXPROJ

mkdir -p "$PROJECT_DIR/$PROJECT_NAME.xcodeproj"

# 6. 더 간단한 방법: xcodegen 사용을 위한 project.yml 생성
echo "📝 project.yml 생성 중..."
cat > "$PROJECT_DIR/project.yml" << EOF
name: $PROJECT_NAME
options:
  bundleIdPrefix: $BUNDLE_ID
  deploymentTarget:
    iOS: "17.0"
targets:
  $PROJECT_NAME:
    type: application
    platform: iOS
    sources:
      - $PROJECT_NAME
    info:
      path: $PROJECT_NAME/Info.plist
      properties:
        CFBundleDisplayName: AI 릴리스 워치
        UIBackgroundModes:
          - fetch
          - processing
        BGTaskSchedulerPermittedIdentifiers:
          - com.ainews.refresh
        NSAppTransportSecurity:
          NSAllowsArbitraryLoads: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: $BUNDLE_ID
        INFOPLIST_FILE: $PROJECT_NAME/Info.plist
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
    capabilities:
      BackgroundModes:
        - fetch
        - processing
EOF

echo ""
echo "✅ 프로젝트 생성 완료!"
echo ""
echo "📍 위치: $PROJECT_DIR"
echo ""
echo "🎯 다음 단계:"
echo ""
echo "  방법 1: 수동으로 Xcode 프로젝트 열기"
echo "    1. Xcode 실행"
echo "    2. File > New > Project"
echo "    3. iOS App 선택, Product Name: $PROJECT_NAME"
echo "    4. 생성된 파일들을 $PROJECT_DIR/$PROJECT_NAME/ 에서 드래그"
echo ""
echo "  방법 2: xcodegen 사용 (설치 필요)"
echo "    brew install xcodegen"
echo "    cd $PROJECT_DIR"
echo "    xcodegen generate"
echo "    open $PROJECT_NAME.xcodeproj"
echo ""
echo "  방법 3: Swift Package로 시작"
echo "    cd $PROJECT_DIR"
echo "    swift package init --type executable"
echo "    # 그 다음 Xcode로 Package.swift 열기"
echo ""

# 7. README 생성
cat > "$PROJECT_DIR/README.md" << 'MDEOF'
# AI 릴리스 워치

## 빠른 시작

### Xcode에서 프로젝트 생성
```bash
1. Xcode 실행
2. File > New > Project (⇧⌘N)
3. iOS > App 선택
4. Product Name: AINewsWatch
5. Interface: SwiftUI
6. Language: Swift
7. Create
```

### 파일 추가
생성된 프로젝트의 AINewsWatch 폴더에서:
- 기존 ContentView.swift 삭제
- 이 폴더의 모든 .swift 파일을 드래그하여 추가
- Info.plist 내용 병합

### Capabilities 설정
1. Target > Signing & Capabilities
2. + Capability > Background Modes
3. ✅ Background fetch
4. ✅ Background processing

### 실행
⌘ + R

## 문제 해결

파일이 추가되지 않으면:
1. 각 파일 선택
2. File Inspector (⌥⌘1)
3. Target Membership > AINewsWatch 체크

빌드 오류가 나면:
1. Product > Clean Build Folder (⇧⌘K)
2. 다시 빌드 (⌘B)
MDEOF

echo "📖 README.md도 생성했습니다"
echo ""
echo "🎉 준비 완료! 이제 Xcode에서 프로젝트를 여세요."
EOF
