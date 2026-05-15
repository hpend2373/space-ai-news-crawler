import SwiftUI

struct ContentView: View {
    @EnvironmentObject var newsMonitor: NewsMonitor
    @State private var selectedSection: NewsSection = .highlights
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 배경 그라디언트
                backgroundGradient
                
                VStack(spacing: 0) {
                    // 상태 헤더
                    statusHeader
                    
                    // 섹션 선택
                    sectionPicker
                    
                    // 뉴스 리스트
                    newsContent
                }
            }
            .navigationTitle("AI 릴리스 워치")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await newsMonitor.manualRefresh()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(newsMonitor.isRefreshing ? 360 : 0))
                            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: newsMonitor.isRefreshing)
                    }
                    .disabled(newsMonitor.isRefreshing)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .task {
                if newsMonitor.newsItems.isEmpty {
                    await newsMonitor.checkAndRefreshIfNeeded()
                    if newsMonitor.newsItems.isEmpty {
                        await newsMonitor.manualRefresh()
                    }
                }
            }
        }
    }
    
    private var backgroundGradient: some View {
        ZStack {
            Color(red: 0.027, green: 0.039, blue: 0.063) // #070A10
                .ignoresSafeArea()
            
            // 그라디언트 오버레이
            RadialGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.357, green: 0.714, blue: 1.0).opacity(0.18),
                    Color.clear
                ]),
                center: .topLeading,
                startRadius: 50,
                endRadius: 400
            )
            .ignoresSafeArea()
            
            RadialGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.357, green: 0.949, blue: 0.776).opacity(0.14),
                    Color.clear
                ]),
                center: .topTrailing,
                startRadius: 50,
                endRadius: 350
            )
            .ignoresSafeArea()
            
            RadialGradient(
                gradient: Gradient(colors: [
                    Color(red: 1.0, green: 0.827, blue: 0.431).opacity(0.10),
                    Color.clear
                ]),
                center: .bottom,
                startRadius: 50,
                endRadius: 450
            )
            .ignoresSafeArea()
        }
    }
    
    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // WiFi 상태
                HStack(spacing: 6) {
                    Image(systemName: newsMonitor.isOnWiFi ? "wifi" : "wifi.slash")
                        .foregroundStyle(newsMonitor.isOnWiFi ? .green : .secondary)
                    Text(newsMonitor.isOnWiFi ? "WiFi 연결됨" : "WiFi 없음")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // 마지막 업데이트
                if let lastUpdate = newsMonitor.lastUpdateTime {
                    Text("업데이트: \(lastUpdate, style: .relative) 전")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // 진행 상태
            if newsMonitor.isRefreshing {
                ProgressView(value: newsMonitor.progress, total: 1.0) {
                    Text(newsMonitor.statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .tint(.blue)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    private var sectionPicker: some View {
        Picker("섹션", selection: $selectedSection) {
            ForEach(NewsSection.allCases) { section in
                Text(section.title).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .padding()
    }
    
    @ViewBuilder
    private var newsContent: some View {
        if newsMonitor.newsItems.isEmpty && !newsMonitor.isRefreshing {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredItems) { item in
                        NewsCard(item: item)
                    }
                }
                .padding()
            }
        }
    }
    
    private var filteredItems: [NewsItem] {
        switch selectedSection {
        case .highlights:
            return newsMonitor.highlights
        case .openai:
            return newsMonitor.newsItems.filter { $0.providerId == "openai" }
        case .anthropic:
            return newsMonitor.newsItems.filter { $0.providerId == "anthropic" }
        case .google:
            return newsMonitor.newsItems.filter { $0.providerId == "google" }
        case .trending:
            return newsMonitor.trendingItems
        case .digest:
            return newsMonitor.digestItems
        case .all:
            return newsMonitor.newsItems
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "newspaper")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("뉴스가 없습니다")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text(newsMonitor.isOnWiFi ? "새로고침을 눌러 뉴스를 가져오세요" : "WiFi에 연결되면 자동으로 업데이트됩니다")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            if newsMonitor.isOnWiFi {
                Button {
                    Task {
                        await newsMonitor.manualRefresh()
                    }
                } label: {
                    Label("새로고침", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .padding()
                        .background(.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
            }
        }
        .padding()
        .frame(maxHeight: .infinity)
    }
}

enum NewsSection: String, CaseIterable, Identifiable {
    case highlights = "하이라이트"
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case google = "Google"
    case trending = "트렌딩"
    case digest = "소식"
    case all = "전체"
    
    var id: String { rawValue }
    var title: String { rawValue }
}

#Preview {
    ContentView()
        .environmentObject(NewsMonitor.shared)
}
