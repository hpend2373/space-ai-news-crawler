import SwiftUI

struct ContentView: View {
    @EnvironmentObject var newsMonitor: NewsMonitor
    @State private var selectedSection: NewsSection = .highlights
    var onBackToHome: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                DS.cream.ignoresSafeArea()

                VStack(spacing: 0) {
                    statusHeader
                    sectionTabs
                    newsContent
                }
            }
            .navigationTitle("AI News")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(DS.cream, for: .navigationBar)
            .toolbar {
                if let onBack = onBackToHome {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onBack) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("홈")
                                    .font(DS.body)
                            }
                            .foregroundStyle(DS.ink)
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: DS.space16) {
                        Button {
                            Task { await newsMonitor.manualRefresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(DS.ink)
                                .rotationEffect(.degrees(newsMonitor.isRefreshing ? 360 : 0))
                                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: newsMonitor.isRefreshing)
                        }
                        .disabled(newsMonitor.isRefreshing)

                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(DS.ink)
                        }
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

    // MARK: - Status Header

    private var statusHeader: some View {
        Group {
            if newsMonitor.isRefreshing {
                VStack(spacing: DS.space8) {
                    ProgressView(value: newsMonitor.progress, total: 1.0)
                        .tint(DS.accentBlue)
                    Text(newsMonitor.statusMessage)
                        .font(DS.caption1)
                        .foregroundStyle(DS.stone)
                }
                .padding(.horizontal, DS.space16)
                .padding(.vertical, DS.space12)
            } else if let lastUpdate = newsMonitor.lastUpdateTime {
                HStack(spacing: DS.space8) {
                    Circle()
                        .fill(DS.accentGreen)
                        .frame(width: 6, height: 6)
                    Text("\(lastUpdate, style: .relative) 전")
                        .font(DS.caption1)
                        .foregroundStyle(DS.stone)

                    if !newsMonitor.generatedAt.isEmpty {
                        Text("·")
                            .foregroundStyle(DS.mist)
                        Text(newsMonitor.generatedAt)
                            .font(DS.caption1)
                            .foregroundStyle(DS.mist)
                    }
                }
                .padding(.vertical, DS.space8)
            }
        }
    }

    // MARK: - Section Tabs (Apple 스타일 캡슐 칩)

    private var sectionTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.space8) {
                ForEach(NewsSection.allCases) { section in
                    let isSelected = selectedSection == section
                    let count = itemCount(for: section)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedSection = section
                        }
                    } label: {
                        HStack(spacing: DS.space4) {
                            Text(section.title)
                                .font(DS.subheadline)
                                .fontWeight(isSelected ? .semibold : .regular)

                            if count > 0 {
                                Text("\(count)")
                                    .font(DS.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(isSelected ? DS.warmWhite.opacity(0.8) : DS.mist)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(isSelected ? DS.ink : DS.sand)
                        )
                        .foregroundStyle(isSelected ? DS.warmWhite : DS.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space12)
        }
    }

    // MARK: - News Content

    @ViewBuilder
    private var newsContent: some View {
        let items = filteredItems
        if newsMonitor.isRefreshing && items.isEmpty {
            loadingState
        } else if items.isEmpty && !newsMonitor.isRefreshing {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: DS.space12) {
                    ForEach(items) { item in
                        NewsCard(item: item)
                    }
                }
                .padding(.horizontal, DS.space16)
                .padding(.top, DS.space4)
                .padding(.bottom, DS.space32)
            }
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: DS.space16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(DS.accentBlue)

            Text("수집 중...")
                .font(DS.title3)
                .foregroundStyle(DS.ink)

            Text("AI 뉴스를 불러오고 있습니다")
                .font(DS.subheadline)
                .foregroundStyle(DS.stone)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredItems: [NewsItem] {
        switch selectedSection {
        case .highlights: return newsMonitor.highlights
        case .openai: return newsMonitor.newsItems.filter { $0.providerId == "openai" }
        case .anthropic: return newsMonitor.newsItems.filter { $0.providerId == "anthropic" }
        case .google: return newsMonitor.newsItems.filter { $0.providerId == "google" }
        case .googleai: return newsMonitor.newsItems.filter { $0.providerId == "googleai" }
        case .notebooklm: return newsMonitor.newsItems.filter { $0.providerId == "notebooklm" }
        case .xai: return newsMonitor.newsItems.filter { $0.providerId == "xai" }
        case .meta: return newsMonitor.newsItems.filter { $0.providerId == "meta" }
        case .trending: return newsMonitor.trendingItems
        case .digest: return newsMonitor.digestItems
        case .all: return newsMonitor.newsItems
        }
    }

    private func itemCount(for section: NewsSection) -> Int {
        switch section {
        case .highlights: return newsMonitor.highlights.count
        case .openai: return newsMonitor.newsItems.filter { $0.providerId == "openai" }.count
        case .anthropic: return newsMonitor.newsItems.filter { $0.providerId == "anthropic" }.count
        case .google: return newsMonitor.newsItems.filter { $0.providerId == "google" }.count
        case .googleai: return newsMonitor.newsItems.filter { $0.providerId == "googleai" }.count
        case .notebooklm: return newsMonitor.newsItems.filter { $0.providerId == "notebooklm" }.count
        case .xai: return newsMonitor.newsItems.filter { $0.providerId == "xai" }.count
        case .meta: return newsMonitor.newsItems.filter { $0.providerId == "meta" }.count
        case .trending: return newsMonitor.trendingItems.count
        case .digest: return newsMonitor.digestItems.count
        case .all: return newsMonitor.newsItems.count
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DS.space16) {
            Image(systemName: "newspaper")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(DS.mist)

            Text("아직 소식이 없습니다")
                .font(DS.title3)
                .foregroundStyle(DS.ink)

            Text("새로고침하여 최신 뉴스를 불러오세요")
                .font(DS.subheadline)
                .foregroundStyle(DS.stone)

            Button {
                Task { await newsMonitor.manualRefresh() }
            } label: {
                Text("새로고침")
                    .font(DS.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, DS.space24)
                    .padding(.vertical, DS.space12)
                    .background(DS.ink)
                    .foregroundStyle(DS.cream)
                    .clipShape(Capsule())
            }
            .padding(.top, DS.space8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 섹션 열거형

enum NewsSection: String, CaseIterable, Identifiable {
    case highlights = "하이라이트"
    case trending = "트렌딩"
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case google = "Google"
    case googleai = "Google AI"
    case notebooklm = "NotebookLM"
    case xai = "xAI"
    case meta = "Meta AI"
    case digest = "소식"
    case all = "전체"

    var id: String { rawValue }
    var title: String { rawValue }
}

#Preview {
    ContentView()
        .environmentObject(NewsMonitor.shared)
}
