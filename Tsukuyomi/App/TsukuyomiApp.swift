import SwiftUI
import AVFoundation

@main
struct TsukuyomiApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var feedStore = FeedStore()
    @State private var settingsStore = SettingsStore()
    @State private var appLogger = AppLogger()
    @State private var audioPlayerStore = AudioPlayerStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(feedStore)
                .environment(settingsStore)
                .environment(appLogger)
                .environment(audioPlayerStore)
                .task {
                    RemoteImageLoader.configureSharedCache()
                    configureAudioSession()
                    audioPlayerStore.bootstrap(logger: appLogger)
                    appLogger.refreshCaptureSession()
                    appLogger.log("Bootstrapping application stores", category: .app)
                    settingsStore.bootstrap(logger: appLogger)
                    await feedStore.bootstrap(logger: appLogger)
                    appLogger.logLifecycle("Application bootstrap finished")
                }
                .onChange(of: scenePhase) { _, newValue in
                    appLogger.logLifecycle("Scene phase changed to \(String(describing: newValue))")
                    if newValue == .active {
                        appLogger.refreshCaptureSession()
                        appLogger.logLifecycle("Application became active and started a new capture session")
                    }
                }
        }
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .moviePlayback,
                options: [.allowAirPlay]
            )
            try AVAudioSession.sharedInstance().setActive(true)
            appLogger.log("Configured audio session for playback", category: .app)
        } catch {
            appLogger.log("Failed to configure audio session: \(error.localizedDescription)", category: .warning)
        }
    }
}
