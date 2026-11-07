import AVFoundation
import Combine
import MediaPlayer
import UIKit

enum MediaSource: String, CaseIterable, Identifiable {
  case applePodcasts
  case appleMusic

  var id: String { rawValue }
  static let selectableSources: [MediaSource] = [.applePodcasts, .appleMusic]
  var title: String {
    switch self {
    case .applePodcasts: return "Apple Podcasts via Shortcuts"
    case .appleMusic: return "Apple Music"
    }
  }
  var systemImage: String {
    switch self {
    case .applePodcasts: return "waveform.badge.mic"
    case .appleMusic: return "music.note"
    }
  }
}

/// Routes media gestures to Apple Podcasts via Shortcuts or Apple Music.
@MainActor
final class MediaRouter: ObservableObject {
  enum ControlError: LocalizedError {
    case shortcutRequired

    var errorDescription: String? {
      "Configure a Shortcut in Settings to control Apple Podcasts. CuffTag cannot control another app's playback directly."
    }
  }

  @Published var activeSource: MediaSource {
    didSet {
      defaults.set(activeSource.rawValue, forKey: "activeSource")
      if activeSource == .appleMusic { requestMusicAccessIfNeeded() }
    }
  }
  @Published var applePodcastsPlayPauseShortcut: String {
    didSet { defaults.set(applePodcastsPlayPauseShortcut, forKey: "applePodcastsPlayPauseShortcut") }
  }
  @Published var applePodcastsSkipForwardShortcut: String {
    didSet { defaults.set(applePodcastsSkipForwardShortcut, forKey: "applePodcastsSkipForwardShortcut") }
  }
  @Published var applePodcastsSkipBackShortcut: String {
    didSet { defaults.set(applePodcastsSkipBackShortcut, forKey: "applePodcastsSkipBackShortcut") }
  }

  private let defaults: UserDefaults
  private let music = MPMusicPlayerController.systemMusicPlayer
  private var bag = Set<AnyCancellable>()

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let savedSource = defaults.string(forKey: "activeSource").flatMap(MediaSource.init)
    activeSource = savedSource == .appleMusic ? .appleMusic : .applePodcasts
    applePodcastsPlayPauseShortcut =
      defaults.string(forKey: "applePodcastsPlayPauseShortcut") ?? ""
    applePodcastsSkipForwardShortcut =
      defaults.string(forKey: "applePodcastsSkipForwardShortcut") ?? "Podcast Skip 30"
    applePodcastsSkipBackShortcut =
      defaults.string(forKey: "applePodcastsSkipBackShortcut") ?? "Podcast Back 15"

    music.beginGeneratingPlaybackNotifications()
    NotificationCenter.default.publisher(
      for: .MPMusicPlayerControllerPlaybackStateDidChange, object: music
    )
    .receive(on: DispatchQueue.main)
    .sink { [weak self] _ in
      guard let self, self.activeSource != .applePodcasts, self.music.playbackState == .playing else { return }
      self.activeSource = .appleMusic
    }
    .store(in: &bag)

  }

  func playPause() throws {
    switch activeSource {
    case .applePodcasts:
      throw ControlError.shortcutRequired
    case .appleMusic:
      music.playbackState == .playing ? music.pause() : music.play()
    }
  }

  var externalPlayPauseShortcut: String? {
    guard activeSource == .applePodcasts else { return nil }
    let trimmed = applePodcastsPlayPauseShortcut.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// If `.applePodcasts` is selected and a Shortcut is configured for Skip/Back, returns its name.
  var externalSkipForwardShortcut: String? {
    guard activeSource == .applePodcasts else { return nil }
    let trimmed = applePodcastsSkipForwardShortcut.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  var externalSkipBackShortcut: String? {
    guard activeSource == .applePodcasts else { return nil }
    let trimmed = applePodcastsSkipBackShortcut.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  func next() throws {
    switch activeSource {
    case .applePodcasts:
      throw ControlError.shortcutRequired
    case .appleMusic: music.skipToNextItem()
    }
  }

  func previous() throws {
    switch activeSource {
    case .applePodcasts:
      throw ControlError.shortcutRequired
    case .appleMusic:
      music.currentPlaybackTime > 3 ? music.skipToBeginning() : music.skipToPreviousItem()
    }
  }

  var isPlaying: Bool {
    switch activeSource {
    case .applePodcasts: return AVAudioSession.sharedInstance().isOtherAudioPlaying
    case .appleMusic: return music.playbackState == .playing
    }
  }

  var nowPlayingDescription: String? {
    switch activeSource {
    case .applePodcasts:
      return "CuffTag cannot read what's playing in Apple Podcasts. Open that app to check playback."
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
  private var ownsSession = false

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  func speak(_ text: String) {
    synthesizer.stopSpeaking(at: .immediate)
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    try? session.setActive(true)
    ownsSession = true
    let utterance = AVSpeechUtterance(string: text)
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
    synthesizer.speak(utterance)
  }

  private func finish() {
    guard ownsSession else { return }
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
