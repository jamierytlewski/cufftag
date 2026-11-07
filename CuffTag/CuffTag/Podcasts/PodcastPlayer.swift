import AVFoundation
import Combine
import MediaPlayer
import UIKit

/// Built-in podcast player with background audio and lock-screen controls.
@MainActor
final class PodcastPlayer: ObservableObject {
  @Published private(set) var episode: Episode?
  @Published private(set) var isPlaying = false
  @Published private(set) var currentTime: Double = 0
  @Published private(set) var duration: Double = 0
  @Published private(set) var artwork: UIImage?
  @Published var rate: Float {
    didSet {
      UserDefaults.standard.set(rate, forKey: "playbackRate")
      if isPlaying && !isDemoMode { player.rate = rate }
      updateNowPlaying()
    }
  }

  let skipForwardSeconds: Double = 30
  let skipBackSeconds: Double = 15

  private let store: PodcastStore
  private let player = AVPlayer()
  private var timeObserver: Any?
  private var bag = Set<AnyCancellable>()
  private var itemBag = Set<AnyCancellable>()
  private var lastSavedTime: Double = 0
  private var isDemoMode = false

  init(store: PodcastStore, restorePlayback: Bool = true) {
    self.store = store
    let savedRate = UserDefaults.standard.float(forKey: "playbackRate")
    rate = savedRate > 0 ? savedRate : 1.0
    player.allowsExternalPlayback = true

    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
    ) { [weak self] time in
      MainActor.assumeIsolated { self?.tick(time.seconds) }
    }

    NotificationCenter.default.publisher(for: AVAudioSession.didBecomeInactiveNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in self?.handleDeactivation($0) }
      .store(in: &bag)
    NotificationCenter.default.publisher(for: AVAudioSession.resumptionRecommendationNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in self?.handleResumptionRecommendation($0) }
      .store(in: &bag)
    NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] note in
        let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
          .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
        if reason == .oldDeviceUnavailable { self?.pause() }
      }
      .store(in: &bag)
    NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] note in
        guard let self, (note.object as? AVPlayerItem) === self.player.currentItem else { return }
        self.episodeFinished()
      }
      .store(in: &bag)

    if restorePlayback { setupRemoteCommands() }

    if restorePlayback, let lastID = UserDefaults.standard.string(forKey: "lastEpisodeID"),
      let last = store.episode(id: lastID)
    {
      load(last)
    }
  }

  func loadDemoEpisode(
    _ episode: Episode,
    currentTime: Double,
    duration: Double,
    isPlaying: Bool,
    artwork: UIImage?
  ) {
    isDemoMode = true
    itemBag.removeAll()
    self.episode = episode
    self.currentTime = currentTime
    self.duration = duration
    self.isPlaying = isPlaying
    self.artwork = artwork
    updateNowPlaying()
  }

  // MARK: - Transport

  func play(_ episode: Episode) {
    if self.episode?.id == episode.id {
      play()
      return
    }
    saveProgress()
    if isDemoMode {
      self.episode = episode
      self.duration = episode.duration ?? 2400
      self.currentTime = store.progress[episode.id] ?? 0
      self.isPlaying = true
      if let url = episode.artworkURL {
        self.artwork = UIImage(contentsOfFile: url.path)
      }
      updateNowPlaying()
      return
    }
    load(episode)
    play()
  }

  func play() {
    guard episode != nil else {
      if let next = store.inProgress.first ?? store.upNext.first { play(next) }
      return
    }
    if isDemoMode {
      isPlaying = true
      updateNowPlaying()
      return
    }
    activateSession()
    player.playImmediately(atRate: rate)
    isPlaying = true
    updateNowPlaying()
  }

  func pause() {
    if !isDemoMode { player.pause() }
    isPlaying = false
    saveProgress()
    updateNowPlaying()
  }

  func togglePlayPause() {
    isPlaying ? pause() : play()
  }

  func skip(by seconds: Double) {
    seek(to: currentTime + seconds)
  }

  func seek(to seconds: Double) {
    let upper = duration > 0 ? duration - 1 : seconds
    let target = min(max(seconds, 0), max(upper, 0))
    currentTime = target
    if isDemoMode {
      saveProgress()
      updateNowPlaying()
      return
    }
    player.seek(to: CMTime(seconds: target, preferredTimescale: 600)) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.saveProgress()
        self?.updateNowPlaying()
      }
    }
  }

  func playNextEpisode() {
    guard let current = episode else {
      play()
      return
    }
    if let next = store.episode(after: current) { play(next) }
  }

  /// Lowers our own volume while the app speaks over the top.
  func duck(_ ducked: Bool) {
    player.volume = ducked ? 0.25 : 1
  }

  // MARK: - Internals

  private func load(_ episode: Episode) {
    itemBag.removeAll()
    let item = AVPlayerItem(url: episode.audioURL)
    item.audioTimePitchAlgorithm = .timeDomain
    player.replaceCurrentItem(with: item)
    self.episode = episode
    duration = episode.duration ?? 0
    UserDefaults.standard.set(episode.id, forKey: "lastEpisodeID")

    let start = store.progress[episode.id] ?? 0
    currentTime = start
    lastSavedTime = start
    if start > 5 {
      player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
    }

    item.publisher(for: \.duration)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] time in
        guard let self, time.isNumeric, time.seconds > 0 else { return }
        self.duration = time.seconds
        self.updateNowPlaying()
      }
      .store(in: &itemBag)

    loadArtwork(for: episode)
  }

  private func tick(_ seconds: Double) {
    guard !isDemoMode, seconds.isFinite, episode != nil else { return }
    currentTime = seconds
    if abs(seconds - lastSavedTime) > 10 { saveProgress() }
  }

  private func saveProgress() {
    guard let episode, currentTime > 0 else { return }
    lastSavedTime = currentTime
    store.setProgress(currentTime, for: episode)
  }

  private func episodeFinished() {
    guard let finished = episode else { return }
    store.setPlayed(true, for: finished)
    if let next = store.episode(after: finished) {
      load(next)
      play()
    } else {
      isPlaying = false
      updateNowPlaying()
    }
  }

  func activateSession() {
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .spokenAudio, options: [])
    try? session.setActive(true)
  }

  /// Our own deactivations (e.g. MediaRouter handing audio back) aren't interruptions.
  private func handleDeactivation(_ note: Notification) {
    let context = note.userInfo?[AVAudioSession.deactivationContextKey]
      as? AVAudioSession.DeactivationContext
    guard context?.source != .app, isPlaying else { return }
    isPlaying = false
    wasInterrupted = true
    saveProgress()
  }

  private func handleResumptionRecommendation(_ note: Notification) {
    let context = note.userInfo?[AVAudioSession.resumptionContextKey]
      as? AVAudioSession.ResumptionContext
    if wasInterrupted, context?.recommendation == .shouldResume { play() }
    wasInterrupted = false
  }

  private var wasInterrupted = false

  // MARK: - Now Playing / lock screen

  private func setupRemoteCommands() {
    let center = MPRemoteCommandCenter.shared()
    center.playCommand.addTarget { [weak self] _ in
      MainActor.assumeIsolated { self?.play() }
      return .success
    }
    center.pauseCommand.addTarget { [weak self] _ in
      MainActor.assumeIsolated { self?.pause() }
      return .success
    }
    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      MainActor.assumeIsolated { self?.togglePlayPause() }
      return .success
    }
    center.skipForwardCommand.preferredIntervals = [NSNumber(value: skipForwardSeconds)]
    center.skipForwardCommand.addTarget { [weak self] _ in
      MainActor.assumeIsolated { self?.skip(by: self?.skipForwardSeconds ?? 30) }
      return .success
    }
    center.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipBackSeconds)]
    center.skipBackwardCommand.addTarget { [weak self] _ in
      MainActor.assumeIsolated { self?.skip(by: -(self?.skipBackSeconds ?? 15)) }
      return .success
    }
    center.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      MainActor.assumeIsolated { self?.seek(to: event.positionTime) }
      return .success
    }
    center.nextTrackCommand.isEnabled = false
    center.previousTrackCommand.isEnabled = false
  }

  private func updateNowPlaying() {
    guard let episode else {
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      return
    }
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: episode.title,
      MPMediaItemPropertyArtist: episode.podcastTitle,
      MPMediaItemPropertyAlbumTitle: episode.podcastTitle,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(rate),
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
    ]
    if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
    if let artwork {
      info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in
        artwork
      }
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  private func loadArtwork(for episode: Episode) {
    artwork = nil
    guard let url = episode.artworkURL ?? store.podcast(id: episode.podcastID)?.artworkURL else {
      return
    }
    Task { [weak self] in
      guard let (data, _) = try? await URLSession.shared.data(from: url),
        let image = UIImage(data: data)
      else { return }
      guard let self, self.episode?.id == episode.id else { return }
      self.artwork = image
      self.updateNowPlaying()
    }
  }
}
