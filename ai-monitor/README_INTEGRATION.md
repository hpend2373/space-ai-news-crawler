# Brief - 통합 뉴스 대시보드

macOS 앱으로 **Stock + Space** 뉴스와 **AI News**를 한곳에서 확인하세요!

## 📱 기능

### 🚀 Stock + Space Brief
- 우주 산업 & 주식 뉴스 수집
- SpaceX, Blue Origin, Rocket Lab 등
- 이슈 자동 감지
- Ollama (qwen3:8b) 번역 지원

### 🤖 AI News Brief
- OpenAI, Anthropic, Google AI 공식 발표
- X (Twitter) + RSS + 공식 블로그
- 중요도 점수 자동 계산
- 24시간 윈도우

## 🏗️ 프로젝트 구조

```
Brief/
├── BriefApp.swift              # 메인 앱 + 모드 선택 화면
├── ContentView.swift            # Stock + Space Brief 뷰
├── AINewsContentView.swift     # AI News Brief 뷰
├── SharedComponents.swift      # 공통 UI 컴포넌트
└── README_INTEGRATION.md       # 이 파일

Python 스크립트:
├── space_stock_brief.py        # Stock + Space 수집기
├── run_space_stock_collector.sh
├── ai_agent.py                 # AI News 수집기
└── run_ai_agent.sh
```

## 🚀 설치 방법

### 1. Python 환경 설정

#### Stock + Space Brief
```bash
cd "~/ai app/stock-space-brief"
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

#### AI News Brief
```bash
cd "~/ai app/ai-news-brief"
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 2. 스크립트 실행 권한 부여

```bash
chmod +x "~/ai app/stock-space-brief/run_space_stock_collector.sh"
chmod +x "~/ai app/ai-news-brief/run_ai_agent.sh"
```

### 3. Xcode에서 빌드

1. Xcode에서 프로젝트 열기
2. **Product → Build** (⌘B)
3. **Product → Run** (⌘R)

## 📖 사용 방법

### 첫 실행
1. 앱 시작 시 **모드 선택 화면** 표시
2. **Stock + Space** 또는 **AI News** 선택
3. 폴더 접근 권한 요청 → **허용** 클릭

### 데이터 수집
- **정보 수집** 버튼 클릭
- 스크립트 실행 → 데이터 파싱 → 자동 새로고침

### 첫 화면으로 돌아가기
- **집 아이콘** (🏠) 버튼 클릭
- 모드 선택 화면으로 즉시 이동
- 다른 모드로 전환 가능

## 🔧 설정

### Stock + Space Brief 경로
```swift
private enum BriefPaths {
    static let root = "~/ai app/stock-space-brief"
    static let reportHTML = root + "/stock_feed.html"
    static let inboxMarkdown = root + "/stock_feed_inbox.md"
    static let collectorScript = root + "/run_space_stock_collector.sh"
}
```

### AI News Brief 경로
```swift
private enum AINewsPaths {
    static let root = "~/ai app/ai-news-brief"
    static let dashboardMarkdown = root + "/dashboard.md"
    static let dashboardHTML = root + "/dashboard.html"
    static let collectorScript = root + "/run_ai_agent.sh"
}
```

**경로 변경**: 위 enum의 `root` 값을 수정하세요.

## 🎨 UI 특징

### 공통
- **모던한 디자인**: 그라디언트, 쉐도우, 애니메이션
- **다크 모드 지원**
- **호버 효과**: 마우스 오버 시 카드 확대
- **자동 번역**: Ollama 기반 영→한 번역

### Stock + Space
- **이슈 강조**: 빨간색 테두리 + "중요" 배지
- **우주경제 섹션**: 보라색 테두리로 구분
- **헤드라인 미리보기**: 축소 시 5개, 확장 시 전체 표시

### AI News
- **프로바이더별 색상**:
  - OpenAI: 초록색
  - Anthropic: 오렌지
  - Google AI: 파란색
- **중요도 점수**: 4점 이상 노란색 별 표시
- **원문 보기**: 확장 시 링크 버튼 표시

## 🐛 문제 해결

### "폴더 접근 권한 필요" 경고
→ **허용** 버튼 클릭 → 폴더 선택

### 수집 버튼 클릭해도 변화 없음
1. Xcode 콘솔 확인 (⌘Y)
2. 로그에서 오류 확인
3. 스크립트 직접 실행 테스트:
   ```bash
   cd "~/ai app/stock-space-brief"
   bash run_space_stock_collector.sh
   ```

### 번역이 안 됨
- Ollama 서버 실행 확인:
  ```bash
  ollama serve
  ```
- qwen3:8b 모델 설치:
  ```bash
  ollama pull qwen3:8b
  ```

## 📝 데이터 파일

### Stock + Space
- **입력**: Python 스크립트가 뉴스 수집
- **출력**: `stock_feed_inbox.md` (마크다운)
- **파싱**: Swift 앱이 md 파일 읽고 UI 생성

### AI News
- **입력**: `ai_agent.py run --hours 24`
- **출력**: `dashboard.md` + `dashboard.html`
- **파싱**: Swift 앱이 md 파일 파싱

## 🔄 업데이트 주기

- **수동**: "정보 수집" 버튼 클릭
- **자동**: (향후 추가 예정)
  - 백그라운드 업데이트
  - WiFi 연결 시 자동 새로고침
  - 정기적인 스케줄링

## 🎯 향후 계획

- [ ] 푸시 알림 (중요 이슈 발생 시)
- [ ] 위젯 지원 (macOS/iOS)
- [ ] 검색 기능
- [ ] 필터링 (날짜, 소스, 키워드)
- [ ] 북마크/즐겨찾기
- [ ] 다크 모드 자동 전환
- [ ] iCloud 동기화

## 📄 라이선스

MIT License

---

**Made with ❤️ by minyeop**
