# AI Release Watch (OpenAI / Anthropic / Google AI)

최근 24시간 내의 공식 업데이트를 모아 HTML 리포트를 생성합니다.

## 하는 일

- OpenAI / Anthropic / Google AI 관련:
  - 공식 X 계정: Nitter 인스턴스를 통해 타임라인을 가져와 파싱
  - 공식 블로그/뉴스: RSS 또는 웹 페이지 파싱
- 별도 섹션:
  - AI News Digest: Google News RSS 검색(`when:1d`) 기반으로 지난 24시간 헤드라인 요약
- 결과물:
  - `dashboard.html` / `dashboard.md` (최신)
  - `reports/report_YYYYMMDD_HHMM.html` / `reports/report_YYYYMMDD_HHMM.md` (히스토리)
  - `last_run.json` (마지막 실행 요약: 카운트/에러/대시보드 업데이트 여부)

## 실행

```bash
cd ~/ai app/ai-monitor
python3 ai_agent.py run
```

윈도우(시간 범위) 변경:

```bash
python3 ai_agent.py run --hours 24
```

## 헬스체크(네트워크/DNS)

소스 접근성(DNS/HTTP/Nitter)을 빠르게 확인합니다.

```bash
python3 ai_agent.py health
```

결과는 `health_last.json`에도 저장됩니다.

## 설정

`config.json`에서 다음을 수정할 수 있습니다.

- 최근 N시간 필터: `filter.hours`
- 전체 실패(모든 소스 실패) 시 재시도:
  - `run.retry_on_total_failure.max_attempts`
  - `run.retry_on_total_failure.delay_seconds`
  - `run.retry_on_total_failure.backoff_multiplier`
  - `run.retry_on_total_failure.max_delay_seconds`
  - `run.retry_on_total_failure.jitter_seconds`
- Nitter 인스턴스/타임아웃: `nitter.instances`, `nitter.timeout_seconds`
- 모니터링 계정/피드:
  - `providers[].x_handles`
  - `providers[].rss`
  - `providers[].web`
- Digest 검색 쿼리 / 최대 아이템 수:
  - `digest.google_news_rss_queries`
  - `digest.max_items_total`
- 뉴스 제목/요약 한국어 번역:
  - `translate.enabled`
  - `translate.provider` (기본: `google_gtx`)
  - `translate.target_lang` (기본: `ko`)
  - `translate.timeout_seconds`
  - `translate.show_original` (원문 함께 표시)

## 주의

- X 소스는 Nitter 인스턴스 상태에 따라 일시적으로 실패할 수 있습니다(리포트의 Source Health에 표시).
- Anthropic 뉴스는 페이지 내 날짜가 "일자" 단위로만 제공되는 경우가 있어, 24시간 필터는 가능한 범위 내에서 최대한 엄격하게 적용합니다.
- 모든 소스가 실패한 실행(`total_failure=true`)에서는 기존 `dashboard.html`/`dashboard.md`를 덮어쓰지 않습니다(마지막 정상 대시보드를 유지).
