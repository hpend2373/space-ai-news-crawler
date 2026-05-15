# 🎯 3분 안에 빌드하고 실행하기

## ✅ 가장 빠른 방법 (복사-붙여넣기)

### 1단계: Xcode 프로젝트 생성 (1분)
```
1. Xcode 실행
2. "Create New Project" 클릭
3. iOS 탭 > App 선택 > Next
4. 입력:
   Product Name: AINewsWatch
   Team: (본인 선택)
   Organization Identifier: com.yourname
   Interface: SwiftUI ← 중요!
   Language: Swift ← 중요!
   Storage: None
   Include Tests: 체크 해제
5. Save (Desktop에 저장)
```

### 2단계: 파일 교체 (1분)
Xcode 좌측 Project Navigator에서:

**삭제할 파일 (우클릭 > Delete > Move to Trash):**
- `AINewsWatchApp.swift` (있으면)
- `ContentView.swift`

**추가할 파일 (Finder에서 드래그):**

현재 폴더에서 다음 파일들을 Xcode 프로젝트 네비게이터의 `AINewsWatch` 폴더로 드래그:

```
✓ AINewsWatchApp.swift
✓ ContentView.swift  
✓ NewsCard.swift
✓ NewsMonitor.swift
✓ NewsCollector.swift
✓ SettingsView.swift
```

**드래그 시 나오는 다이얼로그:**
- ✅ Copy items if needed
- ✅ Create groups (NOT Create folder references)
- ✅ Add to targets: AINewsWatch

### 3단계: Background 설정 (30초)
```
1. Project Navigator에서 최상단 프로젝트 아이콘 클릭
2. TARGETS > AINewsWatch 선택
3. "Signing & Capabilities" 탭 클릭
4. "+ Capability" 버튼 클릭
5. "Background Modes" 검색하여 추가
6. 두 가지 체크:
   ✅ Background fetch
   ✅ Background processing
```

### 4단계: Info.plist 설정 (30초)
```
1. 같은 화면에서 "Info" 탭 클릭
2. Custom iOS Target Properties 아래에서:

   아무 항목이나 우클릭 > Add Row

   추가할 항목들:
   
   A. App Transport Security Settings
      - Type: Dictionary
      - 펼치기 > Add Row:
        Key: Allow Arbitrary Loads
        Type: Boolean
        Value: YES

   B. Permitted background task scheduler identifiers
      - Type: Array
      - 펼치기 > Add Row:
        Item 0: com.ainews.refresh
        Type: String
```

### 5단계: 빌드 및 실행! (⌘R)
```
1. 상단 중앙에서 시뮬레이터 선택:
   iPhone 15 Pro (또는 아무거나)

2. ⌘ + R (또는 재생 버튼 ▶️ 클릭)

3. 기다리면:
   - "Build Succeeded" 메시지
   - 시뮬레이터 부팅
   - 앱 자동 실행!
```

---

## 🎉 성공하면 보이는 화면

```
┌─────────────────────────┐
│ ← AI 릴리스 워치     ⚙️ ↻ │
├─────────────────────────┤
│ 🟢 WiFi 연결됨          │
│                         │
│ [하이라이트] [OpenAI]   │
│ [Anthropic] [Google]    │
│                         │
│ ┌─────────────────────┐ │
│ │ 뉴스가 없습니다      │ │
│ │                     │ │
│ │ 새로고침을 눌러     │ │
│ │ 뉴스를 가져오세요   │ │
│ │                     │ │
│ │   [새로고침 버튼]   │ │
│ └─────────────────────┘ │
└─────────────────────────┘
```

**우측 상단 ↻ 버튼**을 누르면:
- 진행 상황 바 표시
- "OpenAI 수집 중..."
- "Anthropic 수집 중..."
- 1~2분 후 뉴스 카드 표시!

---

## ❌ 빌드 오류 해결

### "Cannot find 'NewsMonitor' in scope"
```
원인: 파일이 Target에 추가되지 않음

해결:
1. Project Navigator에서 NewsMonitor.swift 클릭
2. 우측 File Inspector (⌥⌘1)
3. Target Membership 섹션
4. ✅ AINewsWatch 체크

* 모든 .swift 파일에 대해 반복
```

### "Multiple commands produce Info.plist"
```
원인: Info.plist가 중복됨

해결:
1. Project Navigator에서 Info.plist 검색
2. 중복된 것 하나 삭제
```

### "Signing requires a development team"
```
원인: 서명 설정 필요

해결:
1. Signing & Capabilities 탭
2. Team 선택 (Personal Team 또는 본인 팀)
3. Automatically manage signing 체크
```

### 시뮬레이터가 느리거나 멈춤
```
해결:
1. 시뮬레이터 창에서:
   Device > Erase All Content and Settings
2. Xcode 재시작
3. 다시 ⌘ + R
```

---

## 🚀 테스트하기

### 1. 뉴스 수집 테스트
```
1. 우측 상단 ↻ 버튼 클릭
2. 상태 메시지 관찰:
   - "설정 로드 중..."
   - "뉴스 수집 중..."
   - "OpenAI 수집 중..."
3. 완료되면 뉴스 카드 표시
```

### 2. 섹션 전환 테스트
```
1. 상단 Segmented Control:
   [하이라이트] [OpenAI] [Anthropic] ...
2. 각 섹션 클릭하여 필터링 확인
```

### 3. 뉴스 열기 테스트
```
1. 아무 뉴스 카드 클릭
2. Safari에서 원문 열림
```

### 4. 설정 테스트
```
1. 우측 상단 ⚙️ 아이콘 클릭
2. 시간 범위 변경: 24시간 → 6시간
3. 뒤로가기
4. 새로고침 → 6시간 범위로 수집
```

---

## 🐛 네트워크 문제로 뉴스가 안 나오면?

Nitter가 실패할 수 있으므로 **Mock 데이터로 테스트**:

### ContentView.swift 수정
찾기:
```swift
.navigationTitle("AI 릴리스 워치")
```

그 아래에 추가:
```swift
.onAppear {
    if newsMonitor.newsItems.isEmpty {
        // Mock 데이터 로드
        newsMonitor.newsItems = [
            NewsItem(
                providerId: "openai",
                providerName: "OpenAI",
                source: "X",
                title: "ChatGPT-5 출시 예정",
                url: "https://openai.com",
                publishedAt: Date().addingTimeInterval(-3600),
                summary: "다음 달 출시 예정인 ChatGPT-5는 이전 버전보다 10배 빠른 성능을 제공합니다.",
                rawText: ""
            ),
            NewsItem(
                providerId: "anthropic",
                providerName: "Anthropic",
                source: "WEB",
                title: "Claude 3.5 Sonnet 코딩 성능 향상",
                url: "https://anthropic.com",
                publishedAt: Date().addingTimeInterval(-7200),
                summary: "최신 모델은 소프트웨어 엔지니어링 작업에서 획기적인 개선을 보여줍니다.",
                rawText: ""
            )
        ]
        newsMonitor.highlights = newsMonitor.newsItems
        newsMonitor.lastUpdateTime = Date()
    }
}
```

이제 **즉시 뉴스 카드가 표시**됩니다!

---

## ✨ 완료!

축하합니다! 🎉

이제:
- ✅ 앱이 실행됨
- ✅ 뉴스를 볼 수 있음
- ✅ WiFi 감지 작동
- ✅ 백그라운드 업데이트 준비됨

**다음 단계:**
- 실제 기기에서 테스트
- 번역 기능 추가
- Widget 만들기
- App Store 출시!

---

막히는 부분이 있으면 **정확한 에러 메시지**를 알려주세요!
