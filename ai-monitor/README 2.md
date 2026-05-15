# AI 릴리스 워치 - iOS 앱

Python 스크립트 `ai_agent.py`를 기반으로 한 네이티브 iOS 앱입니다. WiFi 연결 시 자동으로 AI 업계의 최신 뉴스를 수집하고 보여줍니다.

## 주요 기능

### 🔄 자동 업데이트
- **WiFi 감지**: WiFi에 연결되면 자동으로 뉴스 수집 시작
- **백그라운드 새로고침**: 앱이 백그라운드에 있어도 주기적으로 업데이트
- **스마트 간격**: 마지막 업데이트 후 30분이 지나면 자동 새로고침

### 📰 뉴스 소스
1. **공식 채널**
   - OpenAI (X, 블로그)
   - Anthropic (X, 뉴스 페이지)
   - Google AI / DeepMind (X, 블로그)

2. **X 트렌딩**
   - Nitter를 통한 X 검색
   - 참여도(좋아요, 리포스트, 댓글) 기반 정렬
   - AI 관련 키워드 필터링

3. **AI 소식 정리**
   - Google News RSS 통합
   - 최신 업계 뉴스 다이제스트

### 🎨 디자인
- 다크 모드 최적화
- 그라디언트 배경
- 제공사별 컬러 코딩
- 소스별 배지 (X, RSS, 웹, 뉴스)

### 🌏 번역 (예정)
- 자동 번역 지원
- 한국어, 영어, 일본어, 중국어
- 원문 보기 옵션

## 설치 방법

### 1. Xcode 프로젝트 생성
```bash
# Xcode에서 새 프로젝트 생성
# File > New > Project
# iOS > App 선택
# Product Name: AINewsWatch
# Interface: SwiftUI
# Language: Swift
```

### 2. 파일 추가
다음 파일들을 프로젝트에 추가:
- `AINewsWatchApp.swift`
- `ContentView.swift`
- `NewsCard.swift`
- `NewsMonitor.swift`
- `NewsCollector.swift`
- `SettingsView.swift`
- `Info.plist` (프로젝트의 기존 Info.plist에 내용 병합)

### 3. 백그라운드 모드 설정
Xcode에서:
1. 타겟 선택
2. **Signing & Capabilities** 탭
3. **+ Capability** 클릭
4. **Background Modes** 추가
5. 다음 옵션 체크:
   - ✅ Background fetch
   - ✅ Background processing

### 4. 빌드 및 실행
```bash
# 시뮬레이터 또는 실제 기기에서 실행
cmd + R
```

## 사용 방법

### 첫 실행
1. 앱 실행 시 WiFi 연결 확인
2. 우측 상단 새로고침 버튼 탭
3. 뉴스 수집 시작 (1~2분 소요)

### 섹션 탐색
- **하이라이트**: 중요도 높은 뉴스 (키워드 기반)
- **OpenAI**: OpenAI 관련 소식
- **Anthropic**: Anthropic 관련 소식
- **Google**: Google AI / DeepMind 소식
- **트렌딩**: X에서 화제인 AI 관련 포스트
- **소식**: 전체 AI 업계 뉴스 다이제스트
- **전체**: 모든 뉴스

### 설정
우측 상단 톱니바퀴 아이콘:
- 시간 범위 조정 (6/12/24/48시간)
- 자동 새로고침 토글
- 번역 설정
- 소스 상태 확인

## 기술 스택

### Swift 기능
- **SwiftUI**: 선언적 UI
- **Swift Concurrency**: async/await, actors
- **Background Tasks**: BGTaskScheduler
- **Network Framework**: WiFi 감지

### 주요 컴포넌트

#### NewsMonitor
```swift
@MainActor class NewsMonitor: ObservableObject
```
- 앱의 중앙 상태 관리
- WiFi 모니터링
- 뉴스 수집 조율
- 캐시 관리

#### NewsCollector
```swift
actor NewsCollector
```
- 병렬 뉴스 수집
- Nitter 파싱
- RSS 파싱
- 웹 스크래핑 (Anthropic)

#### NewsCard
```swift
struct NewsCard: View
```
- 개별 뉴스 아이템 표시
- 제공사별 색상 구분
- 링크 처리

## 백그라운드 작업

### 작동 방식
1. 앱이 백그라운드로 이동 시 `BGAppRefreshTask` 스케줄링
2. iOS가 적절한 시점에 앱 깨움 (최소 15분 후)
3. WiFi 연결 확인
4. 뉴스 수집 실행
5. 다음 백그라운드 작업 스케줄링

### 테스트 방법
시뮬레이터에서:
```bash
# 백그라운드 작업 강제 실행
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.ainews.refresh"]
```

실제 기기에서:
1. 앱을 백그라운드로 보냄
2. 설정 > 일반 > 백그라운드 앱 새로고침 활성화 확인
3. WiFi 연결 유지
4. 15분~수 시간 대기 (iOS 스케줄링에 따름)

## 주의사항

### 네트워크
- Nitter 인스턴스가 불안정할 수 있음
- 일부 인스턴스는 차단될 수 있음
- 대체 인스턴스를 `NewsMonitor.loadConfiguration()`에서 설정

### 파싱
- HTML 파싱은 정규식 기반 (간단하지만 깨지기 쉬움)
- 프로덕션에서는 `SwiftSoup` 같은 라이브러리 사용 권장
- Nitter HTML 구조 변경 시 파싱 로직 업데이트 필요

### 백그라운드
- iOS의 백그라운드 작업은 보장되지 않음
- 배터리 상태, 네트워크, 사용 패턴에 따라 실행 빈도 달라짐
- 중요한 알림은 Push Notification 사용 권장

### 번역
- 현재는 스텁 구현
- Google Translate API 또는 Apple Translation API 통합 필요
- 비용 고려 (Google Translate는 유료)

## 향후 개선 사항

### 단기
- [ ] 번역 API 통합 (Google Translate 또는 Apple Translation)
- [ ] SwiftSoup으로 HTML 파싱 개선
- [ ] 로컬 푸시 알림 (중요 뉴스 발생 시)
- [ ] 즐겨찾기 기능
- [ ] 공유 기능

### 중기
- [ ] Widget 지원 (Lock Screen / Home Screen)
- [ ] Live Activity (뉴스 수집 진행 상황)
- [ ] Spotlight 검색 통합
- [ ] 다크/라이트 모드 전환
- [ ] iPad 최적화

### 장기
- [ ] macOS 앱 (Mac Catalyst 또는 네이티브)
- [ ] watchOS 컴플리케이션
- [ ] visionOS 지원
- [ ] 서버 기반 수집 (앱은 표시만)
- [ ] AI 기반 요약 (Foundation Models)

## 문제 해결

### WiFi 연결됐는데 자동 새로고침 안 됨
- 설정 > WiFi 시 자동 새로고침 활성화 확인
- 마지막 업데이트 후 30분 이상 경과했는지 확인
- 앱을 완전히 종료 후 재실행

### 뉴스가 수집되지 않음
- 설정 > 소스 상태 확인
- 모든 소스 실패 시 네트워크 문제 가능성
- Nitter 인스턴스 변경 필요할 수 있음

### 백그라운드 작업이 실행 안 됨
- 설정 > 일반 > 백그라운드 앱 새로고침 활성화 확인
- 저전력 모드 비활성화
- WiFi 연결 유지
- iOS가 적절한 시점에 실행 (강제 불가)

## 라이선스

MIT License

## 기여

이슈와 PR 환영합니다!

## 원본

Python 버전: `ai_agent.py`
