# 우주+AI 소식 크롤링

우주 산업과 AI 업계의 최신 소식을 자동으로 수집·번역·브리핑하는 개인 프로젝트.

## 무엇을 하나

OpenAI, Anthropic, Google DeepMind, xAI 등의 공식 블로그·X(트위터) 피드, SpaceX·Rocket Lab 등 우주 기업 관련 뉴스를 주기적으로 크롤링한다. 한국어로 자동 번역해 카드 형태로 정리하고, macOS 데스크톱 앱(Daily Brief)과 HTML 대시보드로 보여 준다.

## 구성

| 폴더 | 역할 |
|------|------|
| `ai app/` + `ai app.xcodeproj` | **Daily Brief** macOS 앱 (SwiftUI). 홈 화면에서 Space News / AI News 두 모드로 진입 |
| `aiapp.md` | 앱 전체 설계·UI 명세 문서 |
| `ai-monitor/` | Python 뉴스 수집 에이전트 — RSS·웹스크래핑·Nitter로 글을 모으고 Google Translate로 번역해 리포트 생성. `config.json`으로 수집 대상 관리, `dashboard.html`로 결과 표시 |
| `stock-space-brief/` | 우주/주식 관련 뉴스 수집기 (`space_stock_brief.py`). 워치리스트 기반으로 SpaceX·Rocket Lab 등 종목별 뉴스 정리 |
| `AINewsWatch/`, `ai news/`, `AI news.playground/` | AI 뉴스 전용 별도 Xcode 프로젝트·플레이그라운드 (실험 버전) |
| `agent-viewer/` | tmux에서 Claude Code 에이전트를 관리하는 Angular Kanban 보드 (외부 도구 — 개발용) |
| `Daily.dmg`, `create_*_dmg.sh` | macOS 앱 배포 패키지·스크립트 |

## 수집 대상 (ai-monitor 기준)

- **AI**: OpenAI, Anthropic, Google AI, DeepMind, NotebookLM, xAI(Grok), 그리고 X 트렌딩 키워드 (GPT/Claude/Gemini/Sora 등)
- **우주**: SpaceX, Rocket Lab, Planet Labs 등 종목 기반 (`stock-space-brief/watchlist.txt`)
- 번역: Google Translate(`google_gtx`) 또는 로컬 Ollama (`qwen3:8b`) 선택 가능

## 빠른 실행

```bash
# ai-monitor 뉴스 수집
cd ai-monitor && bash quick_start.sh

# 우주/주식 브리핑
cd stock-space-brief && bash run_space_stock_collector.sh

# macOS 앱: Xcode에서 "ai app.xcodeproj" 열고 빌드
```
