import SwiftUI
import BackgroundTasks

@main
struct AINewsApp: App {
    @StateObject private var newsMonitor = NewsMonitor.shared
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // 백그라운드 작업 등록
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.ainews.refresh",
            using: nil
        ) { task in
            Task {
                await NewsMonitor.shared.performBackgroundRefresh(task: task as! BGAppRefreshTask)
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(newsMonitor)
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if newPhase == .background {
                        scheduleBackgroundRefresh()
                    } else if newPhase == .active {
                        Task {
                            await newsMonitor.checkAndRefreshIfNeeded()
                        }
                    }
                }
        }
    }
    
    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.ainews.refresh")
        // 15분 후부터 가능하도록 설정
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("백그라운드 작업 스케줄링 실패: \(error)")
        }
    }
}
