import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var newsMonitor: NewsMonitor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DS.cream.ignoresSafeArea()

            List {
                // 데이터 소스 설정
                Section {
                    Picker(selection: Binding(
                        get: { newsMonitor.dataSourceMode },
                        set: { newsMonitor.dataSourceMode = $0 }
                    )) {
                        Text("자동 (서버 우선)")
                            .tag(NewsMonitor.DataSourceMode.auto)
                        Text("서버만 사용")
                            .tag(NewsMonitor.DataSourceMode.serverOnly)
                        Text("직접 수집만")
                            .tag(NewsMonitor.DataSourceMode.directOnly)
                    } label: {
                        Text("데이터 소스")
                            .font(DS.body)
                            .foregroundStyle(DS.ink)
                    }
                    .listRowBackground(DS.warmWhite)

                    if !newsMonitor.lastDataSource.isEmpty {
                        HStack {
                            Text("마지막 소스")
                                .font(DS.body)
                                .foregroundStyle(DS.ink)
                            Spacer()
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(newsMonitor.lastDataSource == "서버" ? DS.accentBlue : DS.accentGreen)
                                    .frame(width: 6, height: 6)
                                Text(newsMonitor.lastDataSource)
                                    .font(DS.body)
                                    .foregroundStyle(DS.stone)
                            }
                        }
                        .listRowBackground(DS.warmWhite)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Label {
                            Text("자동")
                                .font(DS.caption1)
                                .fontWeight(.semibold)
                        } icon: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(DS.stone)

                        Text("서버에 먼저 연결 시도 후, 실패하면 RSS/웹에서 직접 수집합니다. 외출 시에도 뉴스를 볼 수 있습니다.")
                            .font(DS.caption1)
                            .foregroundStyle(DS.mist)
                    }
                    .listRowBackground(DS.warmWhite)
                } header: {
                    Text("데이터 소스")
                        .font(DS.caption1)
                        .fontWeight(.semibold)
                        .foregroundStyle(DS.stone)
                }

                // 서버 설정
                Section {
                    HStack {
                        Text("호스트")
                            .font(DS.body)
                            .foregroundStyle(DS.ink)
                        Spacer()
                        TextField("IP 주소", text: $newsMonitor.serverHost)
                            .font(DS.body)
                            .foregroundStyle(DS.ink)
                            .frame(maxWidth: 180)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    .listRowBackground(DS.warmWhite)

                    HStack {
                        Text("포트")
                            .font(DS.body)
                            .foregroundStyle(DS.ink)
                        Spacer()
                        TextField("포트", value: $newsMonitor.serverPort, format: .number)
                            .font(DS.body)
                            .foregroundStyle(DS.ink)
                            .frame(maxWidth: 100)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    .listRowBackground(DS.warmWhite)

                    LabeledContent("서버 URL", value: newsMonitor.serverURL)
                        .font(DS.caption1)
                        .foregroundStyle(DS.stone)
                        .listRowBackground(DS.warmWhite)

                    Button {
                        Task { await testConnection() }
                    } label: {
                        Text("서버 연결 테스트")
                            .font(DS.body)
                            .foregroundStyle(DS.accentBlue)
                    }
                    .listRowBackground(DS.warmWhite)

                    if !connectionTestResult.isEmpty {
                        Text(connectionTestResult)
                            .font(DS.caption1)
                            .foregroundStyle(connectionTestSuccess ? DS.accentGreen : DS.accentRed)
                            .listRowBackground(DS.warmWhite)
                    }
                } header: {
                    Text("서버 설정")
                        .font(DS.caption1)
                        .fontWeight(.semibold)
                        .foregroundStyle(DS.stone)
                }

                // 수집 설정
                Section {
                    Toggle(isOn: $newsMonitor.autoRefreshEnabled) {
                        Text("자동 새로고침")
                            .font(DS.body)
                            .foregroundStyle(DS.ink)
                    }
                    .tint(DS.accentGreen)
                    .listRowBackground(DS.warmWhite)
                } header: {
                    Text("수집 설정")
                        .font(DS.caption1)
                        .fontWeight(.semibold)
                        .foregroundStyle(DS.stone)
                }

                // 정보
                Section {
                    if !newsMonitor.generatedAt.isEmpty {
                        infoRow("대시보드 생성", value: newsMonitor.generatedAt)
                    }
                    if !newsMonitor.cutoffAt.isEmpty {
                        infoRow("기준(컷오프)", value: newsMonitor.cutoffAt)
                    }
                    infoRow("마지막 업데이트", value: newsMonitor.lastUpdateTime?.formatted() ?? "없음")
                    infoRow("공식 채널 뉴스", value: "\(newsMonitor.newsItems.count)개")
                    infoRow("트렌딩", value: "\(newsMonitor.trendingItems.count)개")
                    infoRow("AI 소식", value: "\(newsMonitor.digestItems.count)개")
                    infoRow("하이라이트", value: "\(newsMonitor.highlights.count)개")
                } header: {
                    Text("정보")
                        .font(DS.caption1)
                        .fontWeight(.semibold)
                        .foregroundStyle(DS.stone)
                }

                // 상태
                if !newsMonitor.sourceHealth.isEmpty {
                    Section {
                        ForEach(newsMonitor.sourceHealth.prefix(10), id: \.self) { msg in
                            Text(msg)
                                .font(DS.caption1)
                                .foregroundStyle(DS.accentOrange)
                                .listRowBackground(DS.warmWhite)
                        }
                    } header: {
                        Text("상태")
                            .font(DS.caption1)
                            .fontWeight(.semibold)
                            .foregroundStyle(DS.stone)
                    }
                }

                // 새로고침 버튼
                Section {
                    Button {
                        Task { await newsMonitor.manualRefresh() }
                    } label: {
                        HStack {
                            Spacer()
                            Text("지금 새로고침")
                                .font(DS.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(DS.accentBlue)
                            Spacer()
                        }
                    }
                    .disabled(newsMonitor.isRefreshing)
                    .listRowBackground(DS.warmWhite)
                }

                // 안내
                Section {
                    Text("자동 모드에서는 Mac 서버를 우선 시도하고, 연결 실패 시 RSS 피드와 웹에서 직접 뉴스를 수집합니다.")
                        .font(DS.caption1)
                        .foregroundStyle(DS.mist)
                        .listRowBackground(DS.warmWhite)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("설정")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Info Row Helper

    private func infoRow(_ label: String, value: String) -> some View {
        LabeledContent {
            Text(value)
                .font(DS.body)
                .foregroundStyle(DS.stone)
        } label: {
            Text(label)
                .font(DS.body)
                .foregroundStyle(DS.ink)
        }
        .listRowBackground(DS.warmWhite)
    }

    // MARK: - 연결 테스트

    @State private var connectionTestResult = ""
    @State private var connectionTestSuccess = false

    private func testConnection() async {
        connectionTestResult = "테스트 중..."
        connectionTestSuccess = false

        let statusURL = "http://\(newsMonitor.serverHost):\(newsMonitor.serverPort)/status"
        guard let url = URL(string: statusURL) else {
            connectionTestResult = "잘못된 URL"
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                connectionTestResult = "서버 응답 오류"
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ok = json["ok"] as? Bool, ok,
               let modified = json["modified"] as? String {
                connectionTestResult = "연결 성공! 최근 업데이트: \(modified)"
                connectionTestSuccess = true
            } else {
                connectionTestResult = "서버 연결됨 (상태 확인 불가)"
                connectionTestSuccess = true
            }
        } catch {
            connectionTestResult = "연결 실패: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(NewsMonitor.shared)
    }
}
