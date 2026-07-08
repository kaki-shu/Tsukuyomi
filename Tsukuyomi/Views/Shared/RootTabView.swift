import SwiftUI

enum AppTab: String, CaseIterable {
    case rss
    case sources
    case pages
    case settings
}

struct RootTabView: View {
    @Environment(AppLogger.self) private var appLogger
    @Environment(AudioPlayerStore.self) private var audioPlayerStore
    @AppStorage("App.SelectedTab") private var selectedTab: AppTab = .rss
    @State private var showingNowPlaying = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(String(localized: "tab.rss", defaultValue: "RSS"), systemImage: "dot.radiowaves.up.forward", value: .rss) {
                NavigationStack {
                    RSSDashboardView()
                }
            }

            Tab(String(localized: "tab.sources", defaultValue: "Sources"), systemImage: "dot.radiowaves.left.and.right", value: .sources) {
                NavigationStack {
                    SourcesView()
                }
            }

            Tab(String(localized: "tab.pages", defaultValue: "Pages"), systemImage: "text.page.badge.magnifyingglass", value: .pages) {
                NavigationStack {
                    PagesView()
                }
            }

            Tab(String(localized: "tab.settings", defaultValue: "Settings"), systemImage: "gearshape", value: .settings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Color.accentCinder)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let item = audioPlayerStore.currentItem {
                PersistentAudioPlayerBar(
                    item: item,
                    isPlaying: audioPlayerStore.isPlaying,
                    openNowPlaying: { showingNowPlaying = true },
                    togglePlayback: { audioPlayerStore.togglePlayback() },
                    stopPlayback: { audioPlayerStore.stop() }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }
        }
        .sheet(isPresented: $showingNowPlaying) {
            NowPlayingView()
        }
        .onAppear {
            appLogger.logUI("Root tab view appeared with selected tab \(selectedTab.rawValue)")
        }
        .onChange(of: selectedTab) { _, newValue in
            appLogger.logUI("Selected tab changed to \(newValue.rawValue)")
        }
    }
}

private struct PersistentAudioPlayerBar: View {
    let item: AudioPlayerStore.PlaybackItem
    let isPlaying: Bool
    let openNowPlaying: () -> Void
    let togglePlayback: () -> Void
    let stopPlayback: () -> Void

    var body: some View {
        Button(action: openNowPlaying) {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.headline)
                    .frame(width: 36, height: 36)
                    .background(Color.buttonSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(Color.accentCinder)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(Color.primaryText)
                    Text(item.subtitle)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.headline)
                        .foregroundStyle(Color.accentCinder)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)

                Button(action: stopPlayback) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.pageBackgroundTop.opacity(0.98), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.buttonSurface.opacity(0.8), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AudioPlayerStore.self) private var audioPlayerStore

    var body: some View {
        NavigationStack {
            ZStack {
                TsukuyomiBackdrop()
                VStack(alignment: .leading, spacing: 24) {
                    if let item = audioPlayerStore.currentItem {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.title)
                                .font(.system(size: 28, weight: .bold, design: .serif))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(item.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: 10) {
                            Slider(
                                value: Binding(
                                    get: { audioPlayerStore.currentTime },
                                    set: { audioPlayerStore.seek(to: $0) }
                                ),
                                in: 0...max(audioPlayerStore.duration, audioPlayerStore.currentTime, 1)
                            )
                            HStack {
                                Text(formatTime(audioPlayerStore.currentTime))
                                Spacer()
                                Text(formatTime(audioPlayerStore.duration))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 20) {
                            Button {
                                audioPlayerStore.togglePlayback()
                            } label: {
                                Image(systemName: audioPlayerStore.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 52))
                                    .foregroundStyle(Color.accentCinder)
                            }
                            .buttonStyle(.plain)

                            Button {
                                audioPlayerStore.stop()
                                dismiss()
                            } label: {
                                Image(systemName: "stop.circle")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle(String(localized: "article.audio.title", defaultValue: "Podcast"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action.close", defaultValue: "Close")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func formatTime(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0:00" }
        let total = Int(value.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
