import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var newsMonitor: NewsMonitor
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            Section("수집 설정") {
                HStack {
                    Text("시간 범위")
                    Spacer()
                    Picker("", selection: $newsMonitor.windowHours) {
                        Text("6시간").tag(6)
                        Text("12시간").tag(12)
                        Text("24시간").tag(24)
                        Text("48시간").tag(48)
                    }
                    .pickerStyle(.menu)
                }
                
                Toggle("WiFi 시 자동 새로고침", isOn: $newsMonitor.autoRefreshEnabled)
            }
            
            Section("번역") {
                Toggle("자동 번역", isOn: $newsMonitor.translationEnabled)
                
                if newsMonitor.translationEnabled {
                    Picker("언어", selection: $newsMonitor.targetLanguage) {
                        Text("한국어").tag("ko")
                        Text("영어").tag("en")
                        Text("일본어").tag("ja")
                        Text("중국어").tag("zh")
                    }
                }
            }
            
            Section("정보") {
                LabeledContent("마지막 업데이트", value: newsMonitor.lastUpdateTime?.formatted() ?? "없음")
                LabeledContent("수집된 뉴스", value: "\(newsMonitor.newsItems.count)개")
                LabeledContent("하이라이트", value: "\(newsMonitor.highlights.count)개")
                LabeledContent("WiFi 상태", value: newsMonitor.isOnWiFi ? "연결됨" : "연결 안 됨")
            }
            
            Section("소스 상태") {
                if newsMonitor.sourceHealth.isEmpty {
                    Text("모든 소스가 정상입니다")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(newsMonitor.sourceHealth.prefix(10), id: \.self) { error in
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    
                    if newsMonitor.sourceHealth.count > 10 {
                        Text("외 \(newsMonitor.sourceHealth.count - 10)개")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section {
                Button("지금 새로고침") {
                    Task {
                        await newsMonitor.manualRefresh()
                    }
                }
                .disabled(newsMonitor.isRefreshing || !newsMonitor.isOnWiFi)
                
                Button("캐시 삭제", role: .destructive) {
                    // TODO: 캐시 삭제 구현
                }
            }
            
            Section {
                Link("Nitter 정보", destination: URL(string: "https://github.com/zedeus/nitter")!)
                Link("개인정보 처리방침", destination: URL(string: "https://example.com/privacy")!)
            }
        }
        .navigationTitle("설정")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(NewsMonitor.shared)
    }
}
