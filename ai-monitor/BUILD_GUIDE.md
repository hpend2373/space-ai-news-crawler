# AI 릴리스 워치 - 빌드 및 실행 가이드

## 🚀 빠른 시작 (5분 안에 실행)

### 1단계: Xcode 프로젝트 생성
```bash
1. Xcode 실행
2. File > New > Project (⇧⌘N)
3. iOS 탭 선택
4. App 템플릿 선택 → Next
5. 다음 정보 입력:
   - Product Name: AINewsWatch
   - Team: (본인 계정)
   - Organization Identifier: com.yourname
   - Interface: SwiftUI
   - Language: Swift
   - Storage: None
6. Create 클릭
```

### 2단계: 파일 추가
생성된 프로젝트에서 기본 파일 삭제하고 제공된 파일로 교체:

```bash
# 1. 기존 파일 삭제
- ContentView.swift (교체할 것이므로)
- AINewsWatchApp.swift (이미 있다면)

# 2. 제공된 파일들을 Xcode 프로젝트 네비게이터로 드래그:
✅ AINewsWatchApp.swift
✅ ContentView.swift
✅ NewsCard.swift
✅ NewsMonitor.swift
✅ NewsCollector.swift
✅ SettingsView.swift
```

**드래그 시 옵션**:
- ✅ Copy items if needed
- ✅ Create groups
- Target: AINewsWatch 체크

### 3단계: Info.plist 설정

**방법 A: GUI로 설정 (추천)**
1. 프로젝트 네비게이터에서 프로젝트 루트 선택
2. TARGETS > AINewsWatch 선택
3. Info 탭으로 이동
4. 오른쪽 + 버튼으로 다음 추가:

```
App Transport Security Settings (Dictionary)
└─ Allow Arbitrary Loads = YES

또는 더 안전하게:
App Transport Security Settings (Dictionary)
└─ Exception Domains (Dictionary)
   ├─ nitter.poast.org (Dictionary)
   │  └─ NSExceptionAllowsInsecureHTTPLoads = YES
   ├─ nitter.privacydev.net (Dictionary)
   │  └─ NSExceptionAllowsInsecureHTTPLoads = YES
   └─ nitter.net (Dictionary)
      └─ NSExceptionAllowsInsecureHTTPLoads = YES

Permitted background task scheduler identifiers (Array)
└─ Item 0 = com.ainews.refresh
```

**방법 B: Info.plist 파일 직접 편집**
제공된 `Info.plist` 내용을 복사하여 프로젝트의 Info.plist에 병합

### 4단계: Background Capabilities 추가
1. TARGETS > AINewsWatch 선택
2. **Signing & Capabilities** 탭
3. **+ Capability** 버튼 클릭
4. **Background Modes** 추가
5. 다음 두 가지 체크:
   - ✅ Background fetch
   - ✅ Background processing

### 5단계: 빌드 및 실행
```bash
# 시뮬레이터 실행
⌘ + R

# 또는 메뉴에서
Product > Run

# 기기 선택
상단 바에서 iPhone 15 Pro (또는 다른 시뮬레이터) 선택
```

---

## 🐛 예상되는 빌드 오류 및 해결

### 오류 1: "Cannot find type 'NewsMonitor' in scope"
**원인**: 파일이 제대로 추가되지 않음
**해결**:
```bash
1. 프로젝트 네비게이터에서 모든 .swift 파일이 보이는지 확인
2. 각 파일 선택 > File Inspector (⌥⌘1)
3. Target Membership에서 AINewsWatch 체크 확인
```

### 오류 2: "Missing required module 'Network'"
**원인**: Framework가 자동으로 링크되지 않음 (보통 자동 해결됨)
**해결**:
```bash
1. TARGETS > AINewsWatch
2. General 탭
3. Frameworks, Libraries, and Embedded Content
4. + 버튼 클릭
5. Network.framework 추가 (보통 필요 없음)
```

### 오류 3: Background task identifier 관련
**원인**: Info.plist 설정 누락
**해결**: 4단계 다시 확인

---

## 🧪 실행 후 테스트

### 1. 초기 화면 확인
- ✅ "AI 릴리스 워치" 타이틀 표시
- ✅ WiFi 상태 표시 (시뮬레이터는 기본 WiFi 연결)
- ✅ "뉴스가 없습니다" 메시지
- ✅ 새로고침 버튼 (우측 상단)

### 2. 수동 새로고침
```bash
1. 우측 상단 새로고침 아이콘 (↻) 탭
2. 상태바에 진행 상황 표시:
   - "설정 로드 중..."
   - "뉴스 수집 중..."
   - "OpenAI 수집 중..."
   - "Anthropic 수집 중..."
   - 등등
3. 1~2분 후 뉴스 카드 표시
```

### 3. 뉴스 확인
- 하이라이트 섹션에 중요 뉴스 표시
- 섹션 피커로 OpenAI, Anthropic, Google 전환
- 각 카드 탭하면 Safari에서 원문 열림

### 4. 설정 확인
```bash
1. 우측 상단 톱니바퀴 아이콘 탭
2. 시간 범위 변경 (24시간 → 6시간)
3. 뒤로가기
4. 새로고침하면 6시간 범위로 수집
```

---

## 📱 실제 기기에서 실행 (선택사항)

### 무료 Apple 계정으로 실행
```bash
1. iPhone을 Mac에 연결
2. Xcode 상단 기기 선택에서 본인 iPhone 선택
3. Signing & Capabilities 탭
   - Team: Personal Team 선택
   - Bundle Identifier: 고유하게 변경 (예: com.yourname.ainewswatch)
4. ⌘ + R 실행
5. iPhone에서:
   설정 > 일반 > VPN 및 기기 관리 > 개발자 앱
   → 본인 계정 신뢰
6. 앱 실행
```

### 백그라운드 작업 테스트 (실제 기기 필요)
```bash
1. 앱 실행 후 뉴스 수집
2. 홈 버튼/제스처로 백그라운드 전환
3. 설정 > 일반 > 백그라운드 앱 새로고침 활성화 확인
4. WiFi 연결 유지
5. 15분~수 시간 후 자동 업데이트
   (iOS 스케줄링에 따라 시간 변동)
```

---

## 🎯 빠른 데모를 위한 팁

실제 Nitter가 느리거나 실패할 수 있으므로, 빠른 테스트를 위해:

### 옵션 1: Mock 데이터 사용
`NewsMonitor.swift`에 다음 함수 추가:

```swift
func loadMockData() {
    newsItems = [
        NewsItem(
            providerId: "openai",
            providerName: "OpenAI",
            source: "X",
            title: "ChatGPT-5 coming soon with major improvements",
            url: "https://twitter.com/OpenAI/status/123",
            publishedAt: Date().addingTimeInterval(-3600),
            summary: "We're excited to announce ChatGPT-5 will launch next month with 10x performance improvements.",
            rawText: ""
        ),
        NewsItem(
            providerId: "anthropic",
            providerName: "Anthropic",
            source: "WEB",
            title: "Claude 3.5 Sonnet achieves breakthrough in coding",
            url: "https://anthropic.com/news/claude-3-5",
            publishedAt: Date().addingTimeInterval(-7200),
            summary: "Our latest model shows significant improvements in software engineering tasks.",
            rawText: ""
        ),
        NewsItem(
            providerId: "google",
            providerName: "Google AI",
            source: "X",
            title: "Gemini 2.0 Flash now available in API",
            url: "https://twitter.com/GoogleAI/status/456",
            publishedAt: Date().addingTimeInterval(-1800),
            summary: "Access our fastest model through the Gemini API starting today.",
            rawText: ""
        )
    ]
    
    highlights = Array(newsItems.prefix(2))
    digestItems = newsItems
    trendingItems = []
    lastUpdateTime = Date()
}
```

그리고 `ContentView.swift`의 `.onAppear`에 추가:
```swift
.onAppear {
    if newsMonitor.newsItems.isEmpty {
        newsMonitor.loadMockData()
    }
}
```

### 옵션 2: 타임아웃 줄이기
`NewsMonitor.swift`의 `loadConfiguration()`에서:
```swift
nitter: NitterConfig(
    instances: [/* ... */],
    timeoutSeconds: 10,  // 30 → 10으로 변경
    maxPostsPerHandle: 5  // 12 → 5로 변경
)
```

---

## 🆘 여전히 안 되면?

### 1. 최소 작동 버전 먼저 확인

간단한 테스트 앱으로 시작:

```swift
// TestApp.swift
import SwiftUI

@main
struct TestApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Hello, AI News!")
                .font(.largeTitle)
        }
    }
}
```

이것이 실행되면 → 기본 설정은 OK
이것도 안 되면 → Xcode 재시작 또는 재설치 필요

### 2. 정확한 오류 메시지 확인
```bash
1. Xcode 하단 Issue Navigator (⌘9)
2. 빨간색 오류 메시지 전체 복사
3. ChatGPT에 붙여넣기 → 정확한 해결책 받기
```

### 3. 시뮬레이터 리셋
```bash
# 시뮬레이터가 이상하게 작동하면
Device > Erase All Content and Settings...
```

---

## ✅ 성공 확인 체크리스트

빌드가 성공하면:
- ✅ Xcode 상단 재생 버튼이 정지 버튼으로 변경
- ✅ 시뮬레이터가 부팅됨 (첫 실행은 느림)
- ✅ 앱 아이콘이 홈 화면에 나타남
- ✅ 앱이 자동으로 실행됨
- ✅ 다크 배경에 그라디언트가 보임

첫 화면이 보이면 성공! 🎉

---

질문이나 오류가 있으면 정확한 에러 메시지를 알려주세요!
```

이 가이드를 따라하시면 됩니다. 어느 단계에서 막히시나요?
