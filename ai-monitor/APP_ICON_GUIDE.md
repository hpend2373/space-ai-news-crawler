# 🎨 Brief 앱 아이콘 가이드

## 디자인 컨셉

**"O" 모양의 원형 링 디자인**
- 원형 = 완전성, 연속성
- 링 = 정보의 순환, Brief(요약)의 핵심
- 그라디언트 = 다양한 뉴스 소스의 융합

### 색상 팔레트

```
배경:
- 다크 그라디언트: #1A1A33 → #0D0D26

메인 링:
- 파랑:  #5CB6FF (Stock + Space)
- 보라:  #9466F2 (중간)
- 핑크:  #F2668E (AI News)

강조:
- 민트:  #5CF2C6 (중앙 글로우)
- 흰색:  #FFFFFF (광택/반짝이)
```

## 📦 파일 구조

```
Brief/
├── AppIconGenerator.swift       # SwiftUI 아이콘 뷰
├── generate_app_icon_svg.py    # SVG 생성기
├── generate_app_icon.sh        # 가이드 스크립트
│
└── Assets.xcassets/
    └── AppIcon.appiconset/
        ├── Contents.json
        ├── icon_16x16.png
        ├── icon_16x16@2x.png
        ├── icon_32x32.png
        ├── icon_32x32@2x.png
        ├── icon_128x128.png
        ├── icon_128x128@2x.png
        ├── icon_256x256.png
        ├── icon_256x256@2x.png
        ├── icon_512x512.png
        └── icon_512x512@2x.png
```

## 🚀 아이콘 생성 방법

### 방법 1: SwiftUI Preview (권장 ⭐)

가장 정확하고 아름다운 결과를 얻을 수 있습니다!

1. **Xcode에서 열기**
   ```bash
   open AppIconGenerator.swift
   ```

2. **Preview 선택**
   - Canvas에서 Preview 활성화 (⌥⌘↩︎)
   - "아이콘 단독 - 풀 디자인" 또는 "미니멀" 선택

3. **이미지 내보내기**
   - 방법 A: Preview 우클릭 → Export as Image
   - 방법 B: ⌘⇧4로 정확히 1024x1024 캡처

4. **리사이징** (선택)
   ```bash
   # sips 사용 (macOS 기본)
   sips -z 1024 1024 icon.png --out AppIcon_1024.png
   ```

### 방법 2: SVG 생성 후 변환

1. **SVG 생성**
   ```bash
   chmod +x generate_app_icon_svg.py
   python3 generate_app_icon_svg.py
   ```
   → `AppIcon_Full.svg`, `AppIcon_Minimal.svg` 생성

2. **PNG 변환**

   **ImageMagick 사용** (권장):
   ```bash
   brew install imagemagick
   magick AppIcon_Full.svg -resize 1024x1024 AppIcon_1024.png
   ```

   **Inkscape 사용**:
   ```bash
   brew install inkscape
   inkscape AppIcon_Full.svg \
     --export-filename=AppIcon_1024.png \
     --export-width=1024
   ```

   **온라인 변환**:
   - [CloudConvert](https://cloudconvert.com/svg-to-png)
   - [SVGOMG](https://jakearchibald.github.io/svgomg/)

### 방법 3: Figma/Sketch (디자이너용)

1. **디자인 스펙**
   ```
   캔버스: 1024 × 1024px
   모서리: 226px 반경 (22.07% 비율)
   
   배경:
   - Linear Gradient
   - #1A1A33 (0°) → #0D0D26 (180°)
   
   메인 링:
   - 중심: 512, 512
   - 외부 반지름: 359px
   - 내부 반지름: 230px (링 두께: 129px)
   - Linear Gradient
     - #5CB6FF (0°)
     - #9466F2 (50°)
     - #F2668E (100°)
   
   광택:
   - Radial Gradient (30%, 30% 중심)
   - White 30% → Transparent
   
   반짝이:
   - 위치: (256, 276), (774, 328), (666, 778)
   - 크기: 13px 원형
   - 색상: White 80%
   - Blur: 1px
   ```

2. **내보내기**
   - Format: PNG
   - Size: 1024 × 1024
   - Scale: 1x

## 📐 모든 크기 생성

macOS 앱 아이콘은 여러 크기가 필요합니다:

```bash
# 1024x1024 원본에서 모든 크기 생성
sizes=(16 32 64 128 256 512 1024)

for size in "${sizes[@]}"; do
  sips -z $size $size AppIcon_1024.png \
    --out "AppIcon_${size}.png"
done

# @2x 버전
sips -z 32 32 AppIcon_1024.png --out "icon_16x16@2x.png"
sips -z 64 64 AppIcon_1024.png --out "icon_32x32@2x.png"
sips -z 256 256 AppIcon_1024.png --out "icon_128x128@2x.png"
sips -z 512 512 AppIcon_1024.png --out "icon_256x256@2x.png"
sips -z 1024 1024 AppIcon_1024.png --out "icon_512x512@2x.png"

# @1x 버전
sips -z 16 16 AppIcon_1024.png --out "icon_16x16.png"
sips -z 32 32 AppIcon_1024.png --out "icon_32x32.png"
sips -z 128 128 AppIcon_1024.png --out "icon_128x128.png"
sips -z 256 256 AppIcon_1024.png --out "icon_256x256.png"
sips -z 512 512 AppIcon_1024.png --out "icon_512x512.png"
```

## 🎯 Xcode에 추가

1. **Assets.xcassets 열기**
   - Xcode 프로젝트 네비게이터에서 `Assets.xcassets` 선택

2. **AppIcon 찾기**
   - 좌측 리스트에서 `AppIcon` 클릭

3. **이미지 추가**
   - 각 크기 슬롯에 해당 이미지를 드래그 앤 드롭
   - 또는 우클릭 → Import...

4. **빌드 확인**
   ```bash
   # 빌드 및 실행
   ⌘R
   
   # Dock/런치패드에서 아이콘 확인
   ```

## 🎨 디자인 버전 비교

### 버전 1: 풀 디자인 (Full Design)
```
특징:
- 그라디언트 배경
- 3색 링 그라디언트
- 광택 효과
- 중앙 글로우
- 반짝이 3개

장점: 풍부한 디테일, 시각적 임팩트
단점: 작은 크기에서 디테일 손실 가능
```

### 버전 2: 미니멀 (Minimal)
```
특징:
- 단색 배경
- 심플한 링
- 최소한의 광택

장점: 모든 크기에서 선명함
단점: 심플할 수 있음
```

**권장**: 풀 디자인 사용 → macOS는 고해상도 디스플레이가 일반적

## 🔍 품질 체크리스트

- [ ] 1024x1024 크기 확인
- [ ] 투명도 없음 (모든 픽셀 불투명)
- [ ] RGB 색상 공간
- [ ] PNG 포맷
- [ ] 모든 크기 생성 완료
- [ ] Xcode에서 경고 없음
- [ ] 실제 기기에서 테스트
- [ ] Dock에서 확인
- [ ] Spotlight에서 확인
- [ ] 런치패드에서 확인

## 💡 팁

### 미리보기
```bash
# Quick Look으로 아이콘 미리보기
qlmanage -p AppIcon_1024.png
```

### 최적화
```bash
# PNG 최적화 (파일 크기 감소)
brew install optipng
optipng -o7 AppIcon_*.png
```

### 검증
```bash
# 이미지 정보 확인
sips -g all AppIcon_1024.png
```

## 📚 참고 자료

- [Apple Human Interface Guidelines - App Icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [macOS App Icon Template](https://developer.apple.com/design/resources/)
- [SF Symbols](https://developer.apple.com/sf-symbols/) (아이콘 영감)

## 🎉 완성!

아이콘이 준비되면:

1. **빌드 & 실행** (⌘R)
2. **Dock에서 확인**
3. **스크린샷 찍기** 📸
4. **공유하기** 🚀

---

**Made with ❤️ for Brief**
