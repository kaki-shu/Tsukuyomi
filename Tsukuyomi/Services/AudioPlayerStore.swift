import Foundation
import Observation
import AVFoundation
import MediaPlayer

@MainActor
@Observable
final class AudioPlayerStore {
    struct PlaybackItem: Equatable {
        var title: String
        var subtitle: String
        var streamURL: URL
        var artworkURL: URL?
    }

    var currentItem: PlaybackItem?
    var isPlaying = false
    var currentTime: Double = 0
    var duration: Double = 0

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var logger: AppLogger?

    func bootstrap(logger: AppLogger) {
        self.logger = logger
        configureRemoteCommands()
        attachObservers()
    }

    func play(
        url: URL,
        title: String,
        subtitle: String,
        artworkURL: URL? = nil,
        autoplay: Bool = true
    ) {
        let item = PlaybackItem(title: title, subtitle: subtitle, streamURL: url, artworkURL: artworkURL)
        if currentItem?.streamURL != url {
            currentItem = item
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            logger?.log("Prepared persistent audio player for \(url.absoluteString)", category: .media)
        } else {
            currentItem = item
        }

        if autoplay {
            player.play()
            isPlaying = true
            logger?.log("Started audio playback for \(url.absoluteString)", category: .media)
        }
        updateNowPlayingInfo()
    }

    func togglePlayback() {
        guard currentItem != nil else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            logger?.log("Paused persistent audio player", category: .media)
        } else {
            player.play()
            isPlaying = true
            logger?.log("Resumed persistent audio player", category: .media)
        }
        updateNowPlayingInfo()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentItem = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        logger?.log("Stopped persistent audio player", category: .media)
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600))
    }

    private func attachObservers() {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                currentTime = time.seconds.isFinite ? time.seconds : 0
                duration = player.currentItem?.duration.seconds.isFinite == true ? player.currentItem?.duration.seconds ?? 0 : 0
                isPlaying = player.rate > 0
                updateNowPlayingInfo()
            }
        }

        statusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                isPlaying = player.timeControlStatus == .playing
                updateNowPlayingInfo()
            }
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true

        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.resumeFromRemote() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.pauseFromRemote() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func resumeFromRemote() {
        guard currentItem != nil else { return }
        player.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    private func pauseFromRemote() {
        player.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    private func updateNowPlayingInfo() {
        guard let currentItem else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentItem.title,
            MPMediaItemPropertyArtist: currentItem.subtitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
