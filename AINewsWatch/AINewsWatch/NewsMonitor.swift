import Foundation
import Network
import BackgroundTasks

@MainActor
class NewsMonitor: ObservableObject {
    static let shared = NewsMonitor()

    // UI 상태
    @Published var newsItems: [NewsItem] = []
    @Published var highlights: [NewsItem] = []
    @Published var trendingItems: [NewsItem] = []
    @Published var digestItems: [NewsItem] = []
    @Published var isRefreshing = false
    @Published var isOnWiFi = false
    @Published var lastUpdateTime: Date?
    @Published var progress: Double = 0
    @Published var statusMessage = ""
    @Published var sourceHealth: [String] = []

    // 설정
    @Published var windowHours = 24
    @Published var autoRefreshEnabled = true
    @Published var translationEnabled = true
    @Published var targetLanguage = "ko"

    // 데이터 소스 모드
    enum DataSourceMode: String {
        case auto = "auto"           // 서버 우선, 실패 시 직접 수집
        case serverOnly = "server"   // 서버만 사용
        case directOnly = "direct"   // 직접 API 수집만 사용
    }

    @Published var dataSourceMode: DataSourceMode {
        didSet { UserDefaults.standard.set(dataSourceMode.rawValue, forKey: "dataSourceMode") }
    }

    @Published var lastDataSource: String = ""  // "서버" 또는 "직접 수집"

    // 서버 설정
    @Published var serverHost: String {
        didSet { UserDefaults.standard.set(serverHost, forKey: "serverHost") }
    }
    @Published var serverPort: Int {
        didSet { UserDefaults.standard.set(serverPort, forKey: "serverPort") }
    }

    var serverURL: String {
        "http://\(serverHost):\(serverPort)/dashboard.md"
    }

    // 대시보드 메타
    @Published var generatedAt: String = ""
    @Published var cutoffAt: String = ""

    private let networkMonitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.ainews.network")
    private let fileManager = FileManager.default

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var cacheDirectory: URL {
        documentsDirectory.appendingPathComponent("Cache", isDirectory: true)
    }

    // 하이라이트 키워드
    private let highSignalKeywords = [
        "gpt-5", "gpt-4", "claude", "gemini", "release", "launch", "announce",
        "api", "model", "breakthrough", "research", "출시", "발표", "공개",
        "릴리스", "업데이트", "신규", "claude code", "opus", "sonnet"
    ]
    private let lowSignalKeywords = [
        "spam", "scam", "airdrop", "giveaway"
    ]

    private init() {
        let savedMode = UserDefaults.standard.string(forKey: "dataSourceMode") ?? "auto"
        self.dataSourceMode = DataSourceMode(rawValue: savedMode) ?? .auto

        self.serverHost = UserDefaults.standard.string(forKey: "serverHost") ?? "127.0.0.1"
        self.serverPort = UserDefaults.standard.integer(forKey: "serverPort")
        if self.serverPort == 0 { self.serverPort = 8765 }

        setupDirectories()
        startNetworkMonitoring()
        loadCachedNews()
    }

    private func setupDirectories() {
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasOnWiFi = self?.isOnWiFi ?? false
                self?.isOnWiFi = path.usesInterfaceType(.wifi)

                if let autoRefresh = self?.autoRefreshEnabled,
                   autoRefresh,
                   !wasOnWiFi,
                   self?.isOnWiFi == true {
                    await self?.checkAndRefreshIfNeeded()
                }
            }
        }
        networkMonitor.start(queue: queue)
    }

    func checkAndRefreshIfNeeded() async {
        guard autoRefreshEnabled else { return }

        if let lastUpdate = lastUpdateTime,
           Date().timeIntervalSince(lastUpdate) < 30 * 60 {
            return
        }

        await refresh()
    }

    func manualRefresh() async {
        await refresh()
    }

    func performBackgroundRefresh(task: BGAppRefreshTask) async {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        if autoRefreshEnabled {
            await refresh()
            task.setTaskCompleted(success: true)
        } else {
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: - 핵심 새로고침 로직

    private func refresh() async {
        guard !isRefreshing else { return }

        isRefreshing = true
        progress = 0
        statusMessage = "연결 중..."
        sourceHealth = []

        defer {
            isRefreshing = false
            progress = 1.0
        }

        switch dataSourceMode {
        case .serverOnly:
            await refreshFromServer()
        case .directOnly:
            await refreshFromDirectAPI()
        case .auto:
            // 서버 먼저 시도, 실패 시 직접 수집
            let serverSuccess = await refreshFromServer()
            if !serverSuccess {
                print("⚠️ 서버 연결 실패, 직접 API 수집으로 전환")
                sourceHealth.append("서버 연결 실패 → 직접 수집 모드")
                await refreshFromDirectAPI()
            }
        }
    }

    // MARK: - 서버에서 가져오기 (기존 방식)

    @discardableResult
    private func refreshFromServer() async -> Bool {
        progress = 0.2
        statusMessage = "서버 대시보드 다운로드 중..."

        guard let markdown = await fetchDashboard() else {
            statusMessage = "서버 연결 실패"
            return false
        }

        progress = 0.6
        statusMessage = "뉴스 파싱 중..."

        let parsed = parseMarkdown(markdown)

        progress = 0.8
        statusMessage = "하이라이트 생성 중..."

        let allOfficialItems = parsed.officialItems
        let allItemsForScoring = allOfficialItems + parsed.digestItems
        let scored = scoreItems(allItemsForScoring)
        let topHighlights = scored.filter { $0.score >= 4 }.prefix(10).map { $0.item }

        progress = 0.9
        statusMessage = "업데이트 중..."

        newsItems = allOfficialItems
        highlights = Array(topHighlights)
        trendingItems = parsed.trendingItems
        digestItems = parsed.digestItems
        lastUpdateTime = Date()
        lastDataSource = "서버"

        saveCache()

        statusMessage = "서버 (\(allOfficialItems.count + parsed.trendingItems.count + parsed.digestItems.count)건)"
        progress = 1.0

        print("✅ 서버 dashboard.md 파싱 완료: 공식 \(allOfficialItems.count)건, 트렌딩 \(parsed.trendingItems.count)건, 소식 \(parsed.digestItems.count)건")
        return true
    }

    // MARK: - 직접 API 수집 (새로운 방식)

    private func refreshFromDirectAPI() async {
        statusMessage = "직접 API 수집 중..."
        progress = 0.1

        let config = NewsConfig.defaultAI
        let collector = NewsCollector(config: config)

        let result = await collector.collect(
            windowHours: windowHours,
            progressHandler: { @MainActor [weak self] (prog: Double, msg: String) in
                self?.progress = 0.1 + prog * 0.7
                self?.statusMessage = msg
            }
        )

        progress = 0.85
        statusMessage = "하이라이트 생성 중..."

        // 소스 건강 상태
        sourceHealth.append(contentsOf: result.sourceHealth)

        // 하이라이트 스코어링
        let allItemsForScoring = result.allItems + result.digestItems
        let scored = scoreItems(allItemsForScoring)
        let topHighlights = scored.filter { $0.score >= 2 }.prefix(15).map { $0.item }

        progress = 0.95
        statusMessage = "업데이트 중..."

        newsItems = result.allItems
        highlights = topHighlights.isEmpty ? Array(result.allItems.prefix(5)) : Array(topHighlights)
        trendingItems = result.trendingItems
        digestItems = result.digestItems
        lastUpdateTime = Date()
        lastDataSource = "직접 수집"
        generatedAt = Date().formatted(date: .abbreviated, time: .shortened)
        cutoffAt = Date().addingTimeInterval(-Double(windowHours) * 3600).formatted(date: .abbreviated, time: .shortened)

        saveCache()

        let total = result.allItems.count + result.trendingItems.count + result.digestItems.count
        statusMessage = "직접 수집 (\(total)건)"
        progress = 1.0

        print("✅ 직접 API 수집 완료: 공식 \(result.allItems.count)건, 소식 \(result.digestItems.count)건")
    }

    // MARK: - 서버 dashboard.md 가져오기

    private func fetchDashboard() async -> String? {
        guard let url = URL(string: serverURL) else {
            sourceHealth.append("잘못된 서버 URL: \(serverURL)")
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8  // 짧게 (fallback 위해)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                sourceHealth.append("서버 응답 오류: HTTP \(code)")
                return nil
            }

            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
                sourceHealth.append("빈 응답")
                return nil
            }

            return text

        } catch {
            sourceHealth.append("서버 연결 실패: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - 마크다운 파싱 (macOS 버전과 동일 로직)

    struct ParsedDashboard {
        let officialItems: [NewsItem]
        let trendingItems: [NewsItem]
        let digestItems: [NewsItem]
    }

    private func parseMarkdown(_ text: String) -> ParsedDashboard {
        let lines = text.components(separatedBy: "\n")

        // 메타데이터 추출
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("- 생성:") {
                generatedAt = t.replacingOccurrences(of: "- 생성:", with: "").trimmingCharacters(in: .whitespaces)
            } else if t.hasPrefix("- 기준(컷오프):") {
                cutoffAt = t.replacingOccurrences(of: "- 기준(컷오프):", with: "").trimmingCharacters(in: .whitespaces)
            }
        }

        // 섹션별 분리
        var segments: [(section: String, provider: String, lines: [String])] = []
        var curSection = ""
        var curProvider = ""
        var curLines: [String] = []

        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)

            if t.hasPrefix("## ") && !t.hasPrefix("### ") {
                if !curSection.isEmpty {
                    segments.append((curSection, curProvider, curLines))
                }
                curSection = String(t.dropFirst(3))
                curProvider = ""
                curLines = []
            } else if t.hasPrefix("### ") {
                if !curProvider.isEmpty || !curLines.isEmpty {
                    segments.append((curSection, curProvider, curLines))
                    curLines = []
                }
                curProvider = String(t.dropFirst(4))
            } else {
                curLines.append(line)
            }
        }
        if !curSection.isEmpty {
            segments.append((curSection, curProvider, curLines))
        }

        // 각 세그먼트를 뉴스 아이템으로 변환
        var officialItems: [NewsItem] = []
        var trendingItems: [NewsItem] = []
        var digestItems: [NewsItem] = []

        for (section, provider, sLines) in segments {
            guard section != "소스 상태" else { continue }

            let rawItems = parseItems(from: sLines)

            switch section {
            case "X 트렌딩 AI":
                let items = rawItems.map { raw in
                    NewsItem(
                        providerId: "x_trending",
                        providerName: "X 트렌딩",
                        source: raw.source,
                        title: raw.title,
                        url: raw.url,
                        publishedAt: raw.date,
                        summary: raw.summary,
                        rawText: "\(raw.title)\n\(raw.summary)",
                        meta: raw.meta
                    )
                }
                trendingItems.append(contentsOf: items)

            case "공식 채널":
                guard !provider.isEmpty else { continue }
                let providerId = providerIdFromName(provider)
                let items = rawItems.map { raw in
                    NewsItem(
                        providerId: providerId,
                        providerName: provider,
                        source: raw.source,
                        title: raw.title,
                        url: raw.url,
                        publishedAt: raw.date,
                        summary: raw.summary,
                        rawText: "\(raw.title)\n\(raw.summary)",
                        meta: raw.meta
                    )
                }
                officialItems.append(contentsOf: items)

            case "AI 소식 정리":
                let items = rawItems.map { raw in
                    NewsItem(
                        providerId: "digest",
                        providerName: "AI 소식",
                        source: raw.source,
                        title: raw.title,
                        url: raw.url,
                        publishedAt: raw.date,
                        summary: raw.summary,
                        rawText: "\(raw.title)\n\(raw.summary)",
                        meta: raw.meta
                    )
                }
                digestItems.append(contentsOf: items)

            default:
                continue
            }
        }

        // 정렬
        officialItems.sort { $0.publishedAt > $1.publishedAt }
        trendingItems.sort { $0.publishedAt > $1.publishedAt }
        digestItems.sort { $0.publishedAt > $1.publishedAt }

        return ParsedDashboard(
            officialItems: officialItems,
            trendingItems: trendingItems,
            digestItems: digestItems
        )
    }

    // 원시 파싱 아이템
    private struct RawParsedItem {
        let provider: String
        let source: String
        let date: Date
        let title: String
        let url: String
        let summary: String
        let meta: String
    }

    private func parseItems(from lines: [String]) -> [RawParsedItem] {
        var items: [RawParsedItem] = []
        let pattern = #"^- \[([^\]]+)\]\[([^\]]+)\] (\d{4}-\d{2}-\d{2} \d{2}:\d{2})\s*(?:KST)?\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        dateFormatter.timeZone = TimeZone(identifier: "Asia/Seoul")

        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            let range = NSRange(trimmed.startIndex..., in: trimmed)

            if let match = regex.firstMatch(in: trimmed, range: range),
               let providerRange = Range(match.range(at: 1), in: trimmed),
               let sourceRange = Range(match.range(at: 2), in: trimmed),
               let tsRange = Range(match.range(at: 3), in: trimmed),
               let titleRange = Range(match.range(at: 4), in: trimmed) {

                let provider = String(trimmed[providerRange])
                let source = String(trimmed[sourceRange])
                let timestamp = String(trimmed[tsRange])
                let title = String(trimmed[titleRange])

                var url = ""
                var metaParts: [String] = []
                var summaryParts: [String] = []

                i += 1

                while i < lines.count {
                    let subLine = lines[i]
                    let subTrimmed = subLine.trimmingCharacters(in: .whitespaces)

                    if subLine.hasPrefix("  ") && subTrimmed.hasPrefix("- ") {
                        let content = String(subTrimmed.dropFirst(2))
                        if content.hasPrefix("http://") || content.hasPrefix("https://") {
                            if url.isEmpty { url = content }
                        } else if content.contains("좋아요") && content.contains("리포스트") {
                            metaParts.append(content)
                        } else if !content.isEmpty {
                            summaryParts.append(content)
                        }
                        i += 1
                    } else if subTrimmed.isEmpty {
                        var peek = i + 1
                        while peek < lines.count && lines[peek].trimmingCharacters(in: .whitespaces).isEmpty {
                            peek += 1
                        }
                        if peek >= lines.count { break }
                        let peekTrimmed = lines[peek].trimmingCharacters(in: .whitespaces)
                        if peekTrimmed.hasPrefix("- [") || peekTrimmed.hasPrefix("## ") || peekTrimmed.hasPrefix("### ") {
                            break
                        }
                        i += 1
                    } else {
                        if subTrimmed.hasPrefix("- [") || subTrimmed.hasPrefix("## ") {
                            break
                        }
                        if !subTrimmed.isEmpty {
                            summaryParts.append(subTrimmed)
                        }
                        i += 1
                    }
                }

                let date = dateFormatter.date(from: timestamp) ?? Date()
                let cleanTitle = Self.stripThinkTags(title)
                let cleanSummary = Self.stripThinkTags(summaryParts.joined(separator: " "))

                items.append(RawParsedItem(
                    provider: provider,
                    source: source,
                    date: date,
                    title: cleanTitle,
                    url: url,
                    summary: cleanSummary,
                    meta: metaParts.joined(separator: " · ")
                ))
            } else {
                i += 1
            }
        }

        return items
    }

    private func providerIdFromName(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("openai") { return "openai" }
        if lower.contains("anthropic") { return "anthropic" }
        if lower.contains("google") || lower.contains("deepmind") { return "google" }
        if lower.contains("meta") { return "meta" }
        if lower.contains("xai") || lower.contains("x.ai") { return "xai" }
        if lower.contains("google ai") || lower.contains("googleai") { return "googleai" }
        if lower.contains("notebooklm") || lower.contains("notebook lm") { return "notebooklm" }
        if lower.contains("trending") || lower.contains("트렌딩") { return "trending" }
        return lower.replacingOccurrences(of: " ", with: "_")
    }

    /// Python 수집기의 <think> 태그 제거
    static func stripThinkTags(_ text: String) -> String {
        var s = text
        while let r = s.range(of: "</think>") {
            s = String(s[r.upperBound...])
        }
        s = s.replacingOccurrences(of: "<think>", with: "")
            .replacingOccurrences(of: "</think>", with: "")
            .replacingOccurrences(of: "/no_think", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let low = s.lowercased()
        if low.hasPrefix("okay,") || low.hasPrefix("ok,") { return "" }
        if low.contains("the user wants") && low.contains("translat") { return "" }
        if low.contains("let me start") && low.contains("translat") { return "" }
        return s
    }

    // MARK: - 하이라이트 스코어링

    private func scoreItems(_ items: [NewsItem]) -> [(item: NewsItem, score: Int)] {
        return items.map { item in
            let text = "\(item.title)\n\(item.summary)\n\(item.rawText)".lowercased()
            var score = 0

            for keyword in highSignalKeywords {
                if text.contains(keyword.lowercased()) {
                    score += 2
                }
            }

            for keyword in lowSignalKeywords {
                if text.contains(keyword.lowercased()) {
                    score -= 2
                }
            }

            if ["X", "RSS", "WEB"].contains(item.source.uppercased()) {
                score += 1
            }

            return (item, score)
        }
    }

    // MARK: - 캐시

    private func loadCachedNews() {
        let cacheFile = cacheDirectory.appendingPathComponent("news_cache.json")

        guard let data = try? Data(contentsOf: cacheFile),
              let cache = try? JSONDecoder().decode(NewsCache.self, from: data) else {
            return
        }

        newsItems = cache.newsItems
        highlights = cache.highlights
        trendingItems = cache.trendingItems
        digestItems = cache.digestItems
        lastUpdateTime = cache.lastUpdateTime
    }

    private func saveCache() {
        let cache = NewsCache(
            newsItems: newsItems,
            highlights: highlights,
            trendingItems: trendingItems,
            digestItems: digestItems,
            lastUpdateTime: lastUpdateTime ?? Date()
        )

        let cacheFile = cacheDirectory.appendingPathComponent("news_cache.json")

        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheFile)
        }
    }
}

// MARK: - Models

struct NewsItem: Identifiable, Codable, Hashable {
    let id: UUID
    let providerId: String
    let providerName: String
    let source: String
    let title: String
    let url: String
    let publishedAt: Date
    let summary: String
    let rawText: String
    let meta: String

    init(
        id: UUID = UUID(),
        providerId: String,
        providerName: String,
        source: String,
        title: String,
        url: String,
        publishedAt: Date,
        summary: String,
        rawText: String,
        meta: String = ""
    ) {
        self.id = id
        self.providerId = providerId
        self.providerName = providerName
        self.source = source
        self.title = title
        self.url = url
        self.publishedAt = publishedAt
        self.summary = summary
        self.rawText = rawText
        self.meta = meta
    }
}

struct NewsCache: Codable {
    let newsItems: [NewsItem]
    let highlights: [NewsItem]
    let trendingItems: [NewsItem]
    let digestItems: [NewsItem]
    let lastUpdateTime: Date
}
