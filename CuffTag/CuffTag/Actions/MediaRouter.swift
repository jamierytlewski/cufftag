import AVFoundation
import Combine
import MediaPlayer
import UIKit

enum MediaSource: String, CaseIterable, Identifiable {
  case podcasts
  case appleMusic

  var id: String { rawValue }
  var title: String { self == .podcasts ? "Podcasts" : "Apple Music" }
  var systemImage: String { self == .podcasts ? "mic.fill" : "music.note" }
}

/// Routes media gestures to whichever source is active (built-in podcasts or Apple Music).
@MainActor
final class MediaRouter: ObservableObject {
  @Published var activeSource: MediaSource {
    didSet {
      UserDefaults.standard.set(activeSource.rawValue, forKey: "activeSource")
      if activeSource == .appleMusic { requestMusicAccessIfNeeded() }
    }
  }

  let player: PodcastPlayer
  private let music = MPMusicPlayerController.systemMusicPlayer
  private var bag = Set<AnyCancellable>()

  init(player: PodcastPlayer) {
    self.player = player
    activeSource =
      UserDefaults.standard.string(forKey: "activeSource").flatMap(MediaSource.init) ?? .podcasts

    music.beginGeneratingPlaybackNotifications()
    NotificationCenter.default.publisher(
      for: .MPMusicPlayerControllerPlaybackStateDidChange, object: music
    )
    .receive(on: DispatchQueue.main)
    .sink { [weak self] _ in
      guard let self, self.music.playbackState == .playing else { return }
      self.activeSource = .appleMusic
    }
    .store(in: &bag)

    player.$isPlaying
      .filter { $0 }
      .sink { [weak self] _ in self?.activeSource = .podcasts }
      .store(in: &bag)
  }

  func playPause() {
    switch activeSource {
    case .podcasts:
      player.togglePlayPause()
    case .appleMusic:
      music.playbackState == .playing ? music.pause() : music.play()
    }
  }

  func next() {
    switch activeSource {
    case .podcasts: player.skip(by: player.skipForwardSeconds)
    case .appleMusic: music.skipToNextItem()
    }
  }

  func previous() {
    switch activeSource {
    case .podcasts:
      player.skip(by: -player.skipBackSeconds)
    case .appleMusic:
      music.currentPlaybackTime > 3 ? music.skipToBeginning() : music.skipToPreviousItem()
    }
  }

  func nextEpisode() {
    activeSource = .podcasts
    player.playNextEpisode()
  }

  var isPlaying: Bool {
    activeSource == .podcasts ? player.isPlaying : music.playbackState == .playing
  }

  var nowPlayingDescription: String? {
    switch activeSource {
    case .podcasts:
      guard let episode = player.episode else { return nil }
      var text = "\(episode.title), from \(episode.podcastTitle)."
      if player.duration > 0 {
        let minutesLeft = Int((player.duration - player.currentTime) / 60 / Double(player.rate))
        if minutesLeft > 0 { text += " \(minutesLeft) minutes left." }
      }
      return text
    case .appleMusic:
      guard MPMediaLibrary.authorizationStatus() == .authorized,
        let item = music.nowPlayingItem, let title = item.title
      else { return nil }
      if let artist = item.artist { return "\(title), by \(artist)." }
      return title
    }
  }

  private func requestMusicAccessIfNeeded() {
    if MPMediaLibrary.authorizationStatus() == .notDetermined {
      MPMediaLibrary.requestAuthorization { _ in }
    }
  }
}

/// Speaks short announcements without stopping whatever is playing.
@MainActor
final class SpeechAnnouncer: NSObject, AVSpeechSynthesizerDelegate {
  private let synthesizer = AVSpeechSynthesizer()
  private let player: PodcastPlayer
  private var ownsSession = false

  init(player: PodcastPlayer) {
    self.player = player
    super.init()
    synthesizer.delegate = self
  }

  func speak(_ text: String) {
    synthesizer.stopSpeaking(at: .immediate)
    if player.isPlaying {
      // Our own podcast is playing: mix over it at reduced volume.
      player.duck(true)
    } else {
      // Duck (not interrupt) other apps such as Apple Music.
      let session = AVAudioSession.sharedInstance()
      try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
      try? session.setActive(true)
      ownsSession = true
    }
    let utterance = AVSpeechUtterance(string: text)
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
    synthesizer.speak(utterance)
  }

  private func finish() {
    player.duck(false)
    guard ownsSession, !player.isPlaying else { return }
    ownsSession = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in self.finish() }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in self.finish() }
  }
}

/// Adjusts system volume via a hidden MPVolumeView (the only public route on iOS).
@MainActor
final class VolumeController {
  let volumeView: MPVolumeView = {
    let view = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 10, height: 10))
    view.alpha = 0.01
    view.isUserInteractionEnabled = false
    return view
  }()

  func set(_ value: Float) {
    guard let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
      slider.setValue(min(max(value, 0), 1), animated: false)
      slider.sendActions(for: .valueChanged)
    }
  }

  func change(by delta: Float) {
    guard let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first else { return }
    let current = volumeView.window != nil
      ? slider.value : AVAudioSession.sharedInstance().outputVolume
    let target = min(max(current + delta, 0), 1)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
      slider.setValue(target, animated: false)
      slider.sendActions(for: .valueChanged)
    }
  }
}
