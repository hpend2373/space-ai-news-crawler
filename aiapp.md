# Daily Brief — macOS 앱 문서

## 앱 개요

**앱 이름:** Daily Brief (번들 표시명: Daily)
**플랫폼:** macOS (SwiftUI, AppKit)
**윈도우 크기:** 780 × 540 (고정)
**윈도우 스타일:** hiddenTitleBar (타이틀바 숨김)
**색상 모드:** 라이트 전용 (`.preferredColorScheme(.light)`)
**언어:** 한국어 UI

---

## 전체 구조

앱은 크게 **3개 화면**으로 구성된다.

1. **홈 화면 (ModeSelectionView)** — 모드 선택
2. **Space News (StockSpaceContentView)** — 우주 산업 뉴스 브리핑
3. **AI News (AINewsContentView)** — AI 업계 뉴스 브리핑

한 번 방문한 모드는 뷰가 메모리에 유지되어, 홈으로 돌아갔다 다시 들어가도 백그라운드 수집·번역 Task가 끊기지 않는다.

---

## 1. 홈 화면 (ModeSelectionView)

### 레이아웃
- 따뜻한 크림색 배경 (`#FAF9F7`)에 블루/테라코타 그라디언트 원형 블러 장식
- 상단: "Daily Brief" 타이틀 (38pt bold) + "어떤 뉴스를 확인하시겠습니까?" 부제
- 중앙: 2장의 **ModeCard**가 수평 배치
- 하단: "홈 버튼으로 언제든 전환할 수 있습니다" 안내 문구

### ModeCard
각 카드는 260 × 290 크기이며, 다음 요소를 포함한다.

| 카드 | 아이콘 | 타이틀 | 부제 | 액센트 컬러 |
|------|--------|--------|------|-------------|
| Space News | `globe.americas.fill` | Space News | "우주 산업 뉴스 브리핑" (수집 중이면 "수집 진행 중...") | spaceBlue |
| AI News | `brain.head.profile` | AI News | "OpenAI · Anthropic · Google AI" (수집 중이면 "수집 진행 중...") | aiTeal (테라코타) |

- 호버 시 카드 1.5% 확대 + 액센트 컬러 보더 표시
- "시작하기" CTA 버튼 (액센트 컬러 배경)

---

## 2. Space News 화면

### 데이터 소스
- **로컬 파일:** `/Users/minyeop/ai app/stock-space-brief/stock_feed_inbox.md`
- **수집 스크립트:** `run_space_stock_collector.sh` → `space_stock_brief.py` 실행
- **워치리스트:** `watchlist.txt` (SpaceX, Rocket Lab, Planet Labs, NASA, 우주경제 등)

### 수집 방식 (Python 백엔드: `space_stock_brief.py`)
- RSS 피드 (Rocket Lab Updates, Planet Pulse, NASA Breaking News, SpaceNews)
- Google News RSS 쿼리 (기업별 키워드 검색)
- 24시간 윈도우 기반 뉴스 수집
- Ollama (qwen3:8b) 로컬 LLM을 이용한 한국어 번역
- HTML 대시보드 + 마크다운 인박스 파일 생성

### 인터페이스 구성

**헤더 영역:**
- ← 뒤로가기 버튼 (홈으로)
- "Space News" 타이틀 + 상태 인디케이터 (초록점=완료, 파랑=수집중, 빨강=실패)
- "정보 수집" 버튼 (수집 중이면 스피너 표시)

**메타데이터 바:**
- 시계 아이콘 + 생성 시각 · 워치리스트 항목 수 · 검색 윈도우 정보
- "원본" 토글 (마크다운 원문 보기)

**메인 콘텐츠:**
- 폴더 접근 권한 경고 배너 (샌드박스 환경에서 필요 시 표시)
- 빈 상태: "데이터를 불러오는 중..." + '정보 수집' 안내
- 데이터 있을 때: `BriefItemCard` 카드 리스트

### BriefItemCard (뉴스 카드)
각 카드는 하나의 주제(기업/카테고리)에 대한 브리핑이다.

**카드 구성:**
- 좌측: 기업 로고 (SpaceX, Rocket Lab, Planet Labs) 또는 SF Symbol 아이콘
- 우측: 제목 + "중요" 배지(이슈 있을 때) + 기사 수/이슈 수/뉴스 수 메타데이터
- 본문: 요약 텍스트 (접힌 상태: 3줄)
- 헤드라인 리스트: 최대 3개 표시, "외 N건 더보기" 버튼으로 확장
- 확장 시: "왜 중요한가" 섹션 + 타임스탬프 + 출처 정보

**색상 규칙:**
- 우주경제 관련: 퍼플 보더
- 이슈 있을 때: 레드 보더
- 일반: 블루 테마

---

## 3. AI News 화면

### 데이터 소스
- **로컬 파일:** `/Users/minyeop/ai app/ai-monitor/dashboard.md`
- **수집 스크립트:** `run_ai_agent.sh` → `ai_agent.py` 실행
- **설정 파일:** `config.json` (프로바이더, 키워드, 번역 설정 등)

### 수집 방식 (Python 백엔드: `ai_agent.py`)
- **X(트위터) 트렌딩:** Nitter 인스턴스를 통한 AI 관련 트렌딩 수집 (9개 인스턴스 자동 로테이션)
  - 검색 쿼리 10개: ChatGPT/Claude/Gemini, AI model/agent, transformer/diffusion 등
  - 쿼리당 최대 80개, 전체 최대 50개 아이템
- **공식 채널 (6개 프로바이더):**
  - OpenAI: X(@OpenAI, @sama) + RSS (openai.com/news/rss.xml)
  - Anthropic: X(@AnthropicAI) + 웹 스크래핑 (anthropic.com/news)
  - Google AI: X(@GoogleAI) + RSS (blog.google AI)
  - Google DeepMind: X(@GoogleDeepMind) + RSS (deepmind.google/blog)
  - NotebookLM: X(@NotebookLM)
  - xAI (Grok): X(@xai, @grok)
- **AI 소식 정리 (Digest):** Google News RSS 쿼리 3개, 최대 12개 아이템
- **번역:** Google GTX 번역 API (한국어), `<think>` 태그 자동 제거
- **출력:** HTML 대시보드 + 마크다운 파일

### 인터페이스 구성

**헤더 영역:**
- ← 뒤로가기 버튼 (홈으로)
- "AI News Brief" 타이틀 + 상태 인디케이터
- "AI 뉴스 수집" 버튼 (테라코타 색상)

**메타데이터 바:**
- 생성 시각 + 기준(컷오프) 시각
- "원본" 토글 (마크다운 원문 보기)

**메인 콘텐츠:**
- 빈 상태: "AI 뉴스를 불러오는 중..." + 수집 안내
- 데이터 있을 때: `AINewsSectionCard` 섹션별 카드 리스트

### AINewsSectionCard (섹션 카드)
대시보드 마크다운의 `## 섹션` / `### 프로바이더`를 파싱하여 3가지 타입으로 분류한다.

| 섹션 타입 | 타이틀 예시 | 아이콘 | 색상 |
|-----------|-------------|--------|------|
| trending | X 트렌딩 AI | flame.fill | 퍼플 |
| official | OpenAI / Anthropic / Google AI 등 | 기업별 SF Symbol 또는 로고 이미지 | 기업별 브랜드 컬러 |
| digest | AI 소식 정리 | newspaper.fill | 레드 |

**카드 구성:**
- 헤더: 기업 로고 또는 아이콘 + 제목 + "인기" 배지(트렌딩) + 건수 + 소스별 분류(X, RSS, 웹, 뉴스)
- 아이템 리스트: 최대 3개 표시 → "외 N건 더보기" 확장
- 각 아이템: 소스 배지(캡슐) + 타임스탬프 + 프로바이더 + 제목 (2줄 제한)
- 확장 시: 요약 텍스트 + "원문 보기" 링크 (NSWorkspace.shared.open으로 브라우저 열기)

### AI 뉴스 아이템 형식
마크다운에서 다음 패턴을 정규식으로 파싱한다:
```
- [프로바이더][소스] 2024-02-15 14:30 제목
  - https://example.com/article
  - 요약 텍스트
```

---

## 디자인 시스템 (SharedComponents.swift)

### AppStyle 컬러 팔레트

| 토큰 | 용도 | HEX |
|------|------|-----|
| pageBg | 메인 배경 | #FAF9F7 (따뜻한 크림) |
| cardBg | 카드 배경 | white |
| surfaceBg | 보조 서피스 | #F7F4F1 |
| borderColor | 테두리 | #E3DFD9 |
| claudeAccent | Claude 테라코타 | #D97757 |
| spaceBlue | Space News 악센트 | 부드러운 블루 |
| trendingPurple | 트렌딩 배지 | 부드러운 퍼플 |
| importantRed | 이슈/중요 | 부드러운 레드 |
| successGreen | 완료 상태 | 부드러운 그린 |

### 브랜드 컬러

| 프로바이더 | 컬러 |
|-----------|------|
| OpenAI | #10A37F (그린) |
| Anthropic | #D97757 (테라코타) |
| Google | 블루 (0.26, 0.52, 0.96) |
| DeepMind | 블루 (#4285F4) |
| NotebookLM | 시안 |

### 레이아웃 토큰

| 토큰 | 값 | 용도 |
|------|-----|------|
| cardRadius | 16pt | 카드 코너 반경 |
| innerRadius | 10pt | 내부 요소 코너 |
| badgeRadius | 6pt | 배지 코너 |
| cardPadding | 14pt | 카드 내부 패딩 |
| sectionSpacing | 12pt | 섹션 간 간격 |
| contentInset | 16pt | 스크롤뷰 좌우 인셋 |

### 공통 컴포넌트

- **AppleCard:** 카드 ViewModifier — 흰색 배경, 미세 그림자, 호버 시 확대 효과
- **SectionHeader:** 섹션 헤더 (아이콘 + 제목)
- **ListRowDivider:** Apple grouped list 스타일 구분선
- **BadgeLabel:** 캡슐형 배지 ("중요", "인기" 등)
- **ActionButton:** macOS 네이티브 `.borderedProminent` 스타일 버튼
- **IconCircle:** 원형 배경 아이콘 (Weather/Stocks 앱 스타일)

---

## 백엔드 아키텍처

### 디렉토리 구조

```
ai app/
├── ai-monitor/              # AI News 백엔드
│   ├── ai_agent.py          # 메인 수집 에이전트
│   ├── config.json          # 프로바이더/키워드/번역 설정
│   ├── run_ai_agent.sh      # 실행 스크립트
│   ├── serve_dashboard.py   # 대시보드 서빙 (포트 8765)
│   ├── dashboard.md         # 수집 결과 마크다운
│   └── dashboard.html       # 수집 결과 HTML
│
├── stock-space-brief/       # Space News 백엔드
│   ├── space_stock_brief.py # 메인 수집 에이전트
│   ├── run_space_stock_collector.sh  # 실행 스크립트
│   ├── serve_space.py       # 대시보드 서빙 (포트 8766)
│   ├── watchlist.txt        # 워치리스트 (기업/키워드)
│   ├── stock_feed_inbox.md  # 수집 결과 마크다운
│   └── stock_feed.html      # 수집 결과 HTML
│
├── ai app/                  # macOS 앱 소스
│   ├── ai_appApp.swift      # 앱 엔트리포인트 (ModeSelectionView)
│   ├── ContentView.swift    # Space News 뷰 + BriefViewModel
│   ├── AINewsContentView.swift  # AI News 뷰 + AINewsViewModel
│   └── SharedComponents.swift   # 디자인 시스템 + 공통 컴포넌트
│
└── AINewsWatch/             # iOS 앱 소스 (별도 프로젝트)
    └── AINewsWatch/
        ├── AINewsWatchApp.swift
        ├── ContentView.swift
        ├── ModeSelectionView.swift
        ├── StockSpaceView.swift
        ├── NewsMonitor.swift
        ├── NewsCollector.swift
        ├── NewsCard.swift
        ├── SettingsView.swift
        └── SharedComponents.swift
```

### 데이터 플로우

```
[RSS/X/웹] → Python 수집기 → .md 파일 → macOS 앱 파싱 → SwiftUI 렌더링
                  ↓
            HTTP 서버 (포트 8765/8766) → iOS 앱 fetch
                                            ↓
                                    직접 RSS/웹 수집 (폴백)
```

### 서버 모드
macOS에서 Python 서버가 실행되면 iOS 앱이 같은 WiFi에서 접근 가능하다.

| 서버 | 포트 | 경로 | 내용 |
|------|------|------|------|
| AI News | 8765 | /dashboard.md | AI 뉴스 대시보드 |
| Space News | 8766 | /inbox.md | 우주 뉴스 인박스 |

---

## 주요 기능 요약

1. **듀얼 모드 뉴스 브리핑:** Space News + AI News 두 가지 모드를 홈 화면에서 전환
2. **로컬 Python 에이전트 수집:** RSS, X(Nitter), 웹 스크래핑, Google News RSS를 통한 뉴스 수집
3. **자동 한국어 번역:** Google GTX API 또는 Ollama 로컬 LLM (qwen3:8b)
4. **Apple HIG 디자인:** Weather/Stocks 앱 스타일의 카드 기반 UI, 호버 효과, 네이티브 컨트롤
5. **백그라운드 유지:** 모드 전환 시에도 수집 Task가 중단되지 않음
6. **샌드박스 폴더 접근:** Security-scoped bookmark으로 파일 시스템 접근 관리
7. **원문 보기:** 마크다운 원본 토글 + 브라우저에서 원문 링크 열기
8. **확장/접기:** 카드별 "더보기/접기" 기능으로 상세 정보 토글
9. **기업 로고:** SpaceX, Rocket Lab, Planet Labs, OpenAI, Anthropic, Google AI 등 로고 이미지 지원
10. **iOS 연동:** HTTP 서버를 통한 iOS 앱 데이터 공유 + 직접 수집 폴백 모드
