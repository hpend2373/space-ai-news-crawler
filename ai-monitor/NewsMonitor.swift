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
    
    private let networkMonitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.ainews.network")
    private var config: NewsConfig?
    private let fileManager = FileManager.default
    
    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private var cacheDirectory: URL {
        documentsDirectory.appendingPathComponent("Cache", isDirectory: true)
    }
    
    private init() {
        setupDirectories()
        loadConfiguration()
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
                
                // WiFi 연결되면 자동 새로고침
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
        guard autoRefreshEnabled, isOnWiFi else { return }
        
        // 마지막 업데이트 후 30분 이상 지났으면 자동 새로고침
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
        
        if isOnWiFi && autoRefreshEnabled {
            await refresh()
            task.setTaskCompleted(success: true)
        } else {
            task.setTaskCompleted(success: false)
        }
    }
    
    private func refresh() async {
        guard !isRefreshing else { return }
        
        isRefreshing = true
        progress = 0
        statusMessage = "설정 로드 중..."
        sourceHealth = []
        
        defer {
            isRefreshing = false
            progress = 1.0
        }
        
        guard let config = config else {
            statusMessage = "설정 파일이 없습니다"
            return
        }
        
        let collector = NewsCollector(config: config)
        
        do {
            // 뉴스 수집
            statusMessage = "뉴스 수집 중..."
            progress = 0.2
            
            let result = await collector.collect(windowHours: windowHours) { prog, msg in
                await MainActor.run {
                    self.progress = 0.2 + (prog * 0.6)
                    self.statusMessage = msg
                }
            }
            
            // 번역 (옵션)
            if translationEnabled {
                statusMessage = "번역 중..."
                progress = 0.8
                await translateItems(result.allItems + result.digestItems + result.trendingItems)
            }
            
            // 하이라이트 생성
            statusMessage = "하이라이트 생성 중..."
            progress = 0.9
            let scored = scoreItems(result.allItems + result.digestItems, config: config)
            let topHighlights = scored.filter { $0.score >= 4 }.prefix(10).map { $0.item }
            
            // UI 업데이트
            newsItems = result.allItems
            highlights = Array(topHighlights)
            trendingItems = result.trendingItems
            digestItems = result.digestItems
            sourceHealth = result.sourceHealth
            lastUpdateTime = Date()
            
            // 캐시 저장
            saveCache()
            
            statusMessage = "완료"
            progress = 1.0
            
        } catch {
            statusMessage = "오류: \(error.localizedDescription)"
        }
    }
    
    private func scoreItems(_ items: [NewsItem], config: NewsConfig) -> [(item: NewsItem, score: Int)] {
        let highSignalKeywords = config.keywords.highSignal
        let lowSignalKeywords = config.keywords.lowSignal
        
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
            
            // 공식 소스 가산점
            if ["X", "RSS", "WEB"].contains(item.source.uppercased()) {
                score += 1
            }
            
            return (item, score)
        }
    }
    
    private func translateItems(_ items: [NewsItem]) async {
        // 간단한 번역 로직 (실제로는 Google Translate API 등 사용)
        // 여기서는 스킵하고 원문 그대로 사용
        // TODO: 번역 API 구현
    }
    
    private func loadConfiguration() {
        // 기본 설정
        config = NewsConfig(
            providers: [
                NewsProvider(
                    id: "openai",
                    name: "OpenAI",
                    xHandles: ["OpenAI", "OpenAIDevs"],
                    rss: [],
                    web: []
                ),
                NewsProvider(
                    id: "anthropic",
                    name: "Anthropic",
                    xHandles: ["AnthropicAI"],
                    rss: [],
                    web: ["https://www.anthropic.com/news"]
                ),
                NewsProvider(
                    id: "google",
                    name: "Google AI",
                    xHandles: ["GoogleAI", "GoogleDeepMind"],
                    rss: [],
                    web: []
                )
            ],
            nitter: NitterConfig(
                instances: [
                    "https://nitter.poast.org",
                    "https://nitter.privacydev.net",
                    "https://nitter.net"
                ],
                timeoutSeconds: 30,
                maxPostsPerHandle: 12
            ),
            keywords: KeywordsConfig(
                highSignal: [
                    "gpt-5", "claude", "gemini", "release", "launch", "announce",
                    "api", "model", "breakthrough", "research"
                ],
                lowSignal: [
                    "spam", "scam", "airdrop", "giveaway"
                ]
            ),
            digest: DigestConfig(
                googleNewsRssQueries: [
                    "OpenAI when:1d",
                    "Anthropic when:1d",
                    "Google AI when:1d",
                    "ChatGPT when:1d",
                    "Claude AI when:1d"
                ],
                maxItemsTotal: 12
            ),
            xTrending: XTrendingConfig(
                enabled: true,
                queries: [
                    "ChatGPT OR GPT-5",
                    "Claude OR Anthropic",
                    "Gemini OR \"Google AI\""
                ],
                maxPostsPerQuery: 24,
                maxItemsTotal: 10,
                minScore: 100
            )
        )
    }
    
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

struct NewsConfig {
    let providers: [NewsProvider]
    let nitter: NitterConfig
    let keywords: KeywordsConfig
    let digest: DigestConfig
    let xTrending: XTrendingConfig
}

struct NewsProvider {
    let id: String
    let name: String
    let xHandles: [String]
    let rss: [String]
    let web: [String]
}

struct NitterConfig {
    let instances: [String]
    let timeoutSeconds: Int
    let maxPostsPerHandle: Int
}

struct KeywordsConfig {
    let highSignal: [String]
    let lowSignal: [String]
}

struct DigestConfig {
    let googleNewsRssQueries: [String]
    let maxItemsTotal: Int
}

struct XTrendingConfig {
    let enabled: Bool
    let queries: [String]
    let maxPostsPerQuery: Int
    let maxItemsTotal: Int
    let minScore: Int
}
