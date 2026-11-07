import Foundation
import JacquardSDK
import SwiftUI

enum ActionCategory: String, CaseIterable, Identifiable {
  case media = "Listening"
  case voice = "Voice"
  case jacket = "Jacket & phone"
  case automation = "Automation"
  var id: String { rawValue }
}

enum ActionKind: String, Codable, CaseIterable, Identifiable {
  case none
  case playPause
  case next
  case previous
  case nextEpisode
  case bookmark
  case volumeUp
  case volumeDown
  case speakNowPlaying
  case speakTime
  case speakBattery
  case findPhone
  case openCamera
  case nextProfile
  case webhook
  case runShortcut

  var id: String { rawValue }

  var title: String {
    switch self {
    case .none: return "Do nothing"
    case .playPause: return "Play / Pause"
    case .next: return "Next track · Skip 30s"
    case .previous: return "Previous track · Back 15s"
    case .nextEpisode: return "Next episode"
    case .bookmark: return "Bookmark this moment"
    case .volumeUp: return "Volume up"
    case .volumeDown: return "Volume down"
    case .speakNowPlaying: return "Say what's playing"
    case .speakTime: return "Say the time"
    case .speakBattery: return "Say jacket battery"
    case .findPhone: return "Find my phone"
    case .openCamera: return "Open Sleeve Camera"
    case .nextProfile: return "Switch profile"
    case .webhook: return "Call a webhook"
    case .runShortcut: return "Run a Shortcut"
    }
  }

  var systemImage: String {
    switch self {
    case .none: return "circle.slash"
    case .playPause: return "playpause.fill"
    case .next: return "forward.fill"
    case .previous: return "backward.fill"
    case .nextEpisode: return "forward.end.fill"
    case .bookmark: return "bookmark.fill"
    case .volumeUp: return "speaker.plus.fill"
    case .volumeDown: return "speaker.minus.fill"
    case .speakNowPlaying: return "waveform"
    case .speakTime: return "clock.fill"
    case .speakBattery: return "battery.75percent"
    case .findPhone: return "iphone.radiowaves.left.and.right"
    case .openCamera: return "camera.fill"
    case .nextProfile: return "person.2.crop.square.stack.fill"
    case .webhook: return "network"
    case .runShortcut: return "square.2.layers.3d.fill"
    }
  }

  var category: ActionCategory {
    switch self {
    case .none, .playPause, .next, .previous, .nextEpisode, .bookmark, .volumeUp, .volumeDown:
      return .media
    case .speakNowPlaying, .speakTime, .speakBattery: return .voice
    case .findPhone, .openCamera, .nextProfile: return .jacket
    case .webhook, .runShortcut: return .automation
    }
  }

  /// The feel-it signature played on the sleeve after the action runs.
  var signature: JacketSignal? {
    switch self {
    case .none, .playPause: return nil  // play/pause picks its own based on the result
    case .next, .nextEpisode: return .skip
    case .previous: return .back
    case .bookmark: return .bookmark
    case .volumeUp, .volumeDown: return .volume
    case .speakNowPlaying, .speakTime, .speakBattery, .findPhone, .openCamera: return nil
    case .nextProfile: return .shift
    case .webhook, .runShortcut: return .confirm
    }
  }

  var parameterPrompt: String? {
    switch self {
    case .webhook: return "https://example.com/hook"
    case .runShortcut: return "Shortcut name"
    default: return nil
    }
  }
}

struct GestureAction: Codable, Equatable {
  var kind: ActionKind
  var parameter: String
  var returnToCuffTag: Bool

  init(kind: ActionKind, parameter: String = "", returnToCuffTag: Bool = false) {
    self.kind = kind
    self.parameter = parameter
    self.returnToCuffTag = returnToCuffTag
  }

  private enum CodingKeys: String, CodingKey { case kind, parameter, returnToCuffTag }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    kind = try values.decode(ActionKind.self, forKey: .kind)
    parameter = try values.decodeIfPresent(String.self, forKey: .parameter) ?? ""
    // Keep the callback behavior of shortcuts assigned before this option existed.
    returnToCuffTag = try values.decodeIfPresent(Bool.self, forKey: .returnToCuffTag)
      ?? (kind == .runShortcut)
  }
}

extension JQGesture: @retroactive Identifiable {
  public var id: Int { rawValue }

  /// The four gestures the Levi's Trucker sleeve recognises.
  static let jacketGestures: [JQGesture] = [.doubleTap, .brushIn, .brushOut, .shortCover]

  /// Defined by the SDK for other Jacquard gear; the Levi's sleeve may never report them.
  static let experimentalGestures: [JQGesture] = [.brushUp, .brushDown]

  var friendlyName: String {
    switch self {
    case .noInference: return "None"
    case .doubleTap: return "Double tap"
    case .brushIn: return "Brush in"
    case .brushOut: return "Brush out"
    case .shortCover: return "Cover"
    case .brushUp: return "Brush up"
    case .brushDown: return "Brush down"
    }
  }

  var hint: String {
    switch self {
    case .noInference: return ""
    case .doubleTap: return "Tap the cuff twice"
    case .brushIn: return "Swipe toward your body"
    case .brushOut: return "Swipe away from your body"
    case .shortCover: return "Rest your palm on the cuff"
    case .brushUp: return "Swipe up the sleeve"
    case .brushDown: return "Swipe down the sleeve"
    }
  }

  var symbol: String {
    switch self {
    case .noInference: return "hand.raised"
    case .doubleTap: return "hand.tap.fill"
    case .brushIn: return "arrow.left.to.line"
    case .brushOut: return "arrow.right.to.line"
    case .shortCover: return "hand.raised.fill"
    case .brushUp: return "arrow.up.to.line"
    case .brushDown: return "arrow.down.to.line"
    }
  }
}

struct GestureProfile: Codable, Identifiable, Equatable {
  var id = UUID()
  var name: String
  var symbol: String
  var base: [String: GestureAction]
  var shifted: [String: GestureAction]

  static func key(_ gesture: JQGesture) -> String { String(gesture.rawValue) }

  // Levi's sleeves only know four gestures, so Cover doubles as a "shift" key:
  // Cover then Double tap / Brush in / Brush out within ~1.4 s runs the alternate action.

  static let everyday = GestureProfile(
    name: "Everyday", symbol: "figure.walk",
    base: [
      key(.doubleTap): .init(kind: .playPause),
      key(.brushIn): .init(kind: .next),
      key(.brushOut): .init(kind: .previous),
      key(.shortCover): .init(kind: .speakNowPlaying),
    ],
    shifted: [
      key(.doubleTap): .init(kind: .bookmark),
      key(.brushIn): .init(kind: .volumeUp),
      key(.brushOut): .init(kind: .volumeDown),
    ])

  static let ride = GestureProfile(
    name: "Ride", symbol: "bicycle",
    base: [
      key(.doubleTap): .init(kind: .playPause),
      key(.brushIn): .init(kind: .volumeUp),
      key(.brushOut): .init(kind: .volumeDown),
      key(.shortCover): .init(kind: .speakTime),
    ],
    shifted: [
      key(.doubleTap): .init(kind: .speakNowPlaying),
      key(.brushIn): .init(kind: .next),
      key(.brushOut): .init(kind: .previous),
    ])

  static let focus = GestureProfile(
    name: "Focus", symbol: "moon.stars.fill",
    base: [
      key(.doubleTap): .init(kind: .playPause),
      key(.brushIn): .init(kind: .nextEpisode),
      key(.shortCover): .init(kind: .speakTime),
    ],
    shifted: [
      key(.doubleTap): .init(kind: .speakBattery),
      key(.brushIn): .init(kind: .findPhone),
    ])
}

@MainActor
final class GestureSettings: ObservableObject {
  @Published private(set) var profiles: [GestureProfile] = []
  @Published var activeProfileID: UUID {
    didSet { defaults.set(activeProfileID.uuidString, forKey: "activeProfile") }
  }
  @Published var hapticConfirmation: Bool {
    didSet { defaults.set(hapticConfirmation, forKey: "hapticConfirmation") }
  }
  @Published var spokenConfirmation: Bool {
    didSet { defaults.set(spokenConfirmation, forKey: "spokenConfirmation") }
  }
  /// When on, Cover arms the alternate layer for the next gesture instead of acting immediately.
  @Published var coverIsShift: Bool {
    didSet { defaults.set(coverIsShift, forKey: "coverIsShift") }
  }

  static let shiftWindow: TimeInterval = 1.4
  private let storageKey = "gestureProfiles.v3"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    hapticConfirmation = defaults.object(forKey: "hapticConfirmation") as? Bool ?? true
    spokenConfirmation = defaults.bool(forKey: "spokenConfirmation")
    coverIsShift = defaults.object(forKey: "coverIsShift") as? Bool ?? true

    var loaded: [GestureProfile] = []
    if let data = defaults.data(forKey: storageKey),
      let saved = try? JSONDecoder().decode([GestureProfile].self, from: data)
    {
      loaded = saved
    }
    if loaded.isEmpty {
      var everyday = GestureProfile.everyday
      // Carry over mappings from the first version of the app.
      if let data = defaults.data(forKey: "gestureActions.v1"),
        let old = try? JSONDecoder().decode([String: GestureAction].self, from: data)
      {
        everyday.base = old
      }
      loaded = [everyday, .ride, .focus]
    }
    profiles = loaded
    activeProfileID =
      defaults.string(forKey: "activeProfile").flatMap(UUID.init).flatMap { id in
        loaded.contains { $0.id == id } ? id : nil
      } ?? loaded[0].id
    save()
  }

  var activeProfile: GestureProfile {
    profiles.first { $0.id == activeProfileID } ?? profiles[0]
  }

  func action(for gesture: JQGesture, shifted: Bool = false, in profileID: UUID? = nil)
    -> GestureAction
  {
    let profile = profiles.first { $0.id == (profileID ?? activeProfileID) } ?? activeProfile
    let layer = shifted ? profile.shifted : profile.base
    return layer[GestureProfile.key(gesture)] ?? .init(kind: .none)
  }

  func set(_ action: GestureAction, for gesture: JQGesture, shifted: Bool, in profileID: UUID) {
    guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
    if shifted {
      profiles[index].shifted[GestureProfile.key(gesture)] = action
    } else {
      profiles[index].base[GestureProfile.key(gesture)] = action
    }
    save()
  }

  func binding(for gesture: JQGesture, shifted: Bool, in profileID: UUID) -> Binding<GestureAction> {
    Binding(
      get: { self.action(for: gesture, shifted: shifted, in: profileID) },
      set: { self.set($0, for: gesture, shifted: shifted, in: profileID) })
  }

  /// Gestures that can be used as the second half of a Cover chord.
  static let chordGestures: [JQGesture] = [.doubleTap, .brushIn, .brushOut]

  @discardableResult
  func cycleProfile() -> GestureProfile {
    let index = profiles.firstIndex { $0.id == activeProfileID } ?? 0
    activeProfileID = profiles[(index + 1) % profiles.count].id
    return activeProfile
  }

  func activate(named name: String) -> GestureProfile? {
    guard let match = profiles.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame })
    else { return nil }
    activeProfileID = match.id
    return match
  }

  func addProfile() -> GestureProfile {
    var profile = activeProfile
    profile.id = UUID()
    profile.name = "New profile"
    profile.symbol = "sparkles"
    profiles.append(profile)
    save()
    return profile
  }

  func update(_ profile: GestureProfile) {
    guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
    profiles[index] = profile
    save()
  }

  func delete(_ profile: GestureProfile) {
    guard profiles.count > 1 else { return }
    profiles.removeAll { $0.id == profile.id }
    if activeProfileID == profile.id { activeProfileID = profiles[0].id }
    save()
  }

  func resetToDefaults() {
    profiles = [GestureProfile.everyday, .ride, .focus].map { profile -> GestureProfile in
      var copy = profile
      copy.id = UUID()
      return copy
    }
    activeProfileID = profiles[0].id
    save()
  }

  private func save() {
    if let data = try? JSONEncoder().encode(profiles) {
      defaults.set(data, forKey: storageKey)
    }
  }
}
