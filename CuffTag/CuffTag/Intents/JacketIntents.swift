import AppIntents
import Foundation

// Everything here runs in the app process (no extension), so the BLE connection, podcast player
// and settings are shared with the app. With a free Apple ID this needs no extra entitlements.

struct JacketUnreachable: Error, CustomLocalizedStringResourceConvertible {
  var localizedStringResource: LocalizedStringResource {
    "Couldn't reach your jacket. Make sure the tag is charged and snapped in."
  }
}

struct LegacyPodcastPlayerUnavailable: Error, CustomLocalizedStringResourceConvertible {
  var localizedStringResource: LocalizedStringResource {
    "CuffTag now keeps your library in Apple Podcasts. Use Apple's playback actions in Shortcuts instead of the old CuffTag player."
  }
}

@MainActor
private func connectedServices() async throws -> AppServices {
  let services = AppServices.shared
  guard await services.tag.waitUntilConnected() else { throw JacketUnreachable() }
  return services
}

// MARK: - Enums

enum SignalOption: String, AppEnum {
  case nudge, alert, hello, confirm, bookmark, error

  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Signal"
  static var caseDisplayRepresentations: [SignalOption: DisplayRepresentation] = [
    .nudge: .init(title: "Nudge", subtitle: "Three gentle taps + pink light"),
    .alert: .init(title: "Alert", subtitle: "One long buzz + red flashes"),
    .hello: .init(title: "Hello", subtitle: "A warm rising swell"),
    .confirm: .init(title: "Done", subtitle: "A short tap + white light"),
    .bookmark: .init(title: "Bookmark", subtitle: "Tap, then swell"),
    .error: .init(title: "Didn't work", subtitle: "Two low pulses"),
  ]

  var signal: JacketSignal { JacketSignal.named(rawValue) ?? .confirm }
}

enum LightColor: String, AppEnum {
  case copper, indigo, cyan, white, green, amber, red, violet, pink

  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Colour"
  static var caseDisplayRepresentations: [LightColor: DisplayRepresentation] = [
    .copper: "Copper", .indigo: "Indigo", .cyan: "Cyan", .white: "White", .green: "Green",
    .amber: "Amber", .red: "Red", .violet: "Violet", .pink: "Pink",
  ]

  var rgb: RGB {
    switch self {
    case .copper: return .copper
    case .indigo: return .indigo
    case .cyan: return .cyan
    case .white: return .white
    case .green: return .green
    case .amber: return .amber
    case .red: return .red
    case .violet: return .violet
    case .pink: return .pink
    }
  }
}

enum PodcastCommand: String, AppEnum {
  case playPause, play, pause, skipForward, skipBack, nextEpisode, bookmark

  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Podcast command"
  static var caseDisplayRepresentations: [PodcastCommand: DisplayRepresentation] = [
    .playPause: "Play/Pause", .play: "Play", .pause: "Pause", .skipForward: "Skip forward 30s",
    .skipBack: "Back 15s", .nextEpisode: "Next episode", .bookmark: "Bookmark this moment",
  ]
}

// MARK: - Profiles as entities

struct ProfileEntity: AppEntity {
  let id: UUID
  let name: String

  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Gesture profile"
  static var defaultQuery = ProfileQuery()
  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ProfileQuery: EntityQuery {
  @MainActor
  private func all() -> [ProfileEntity] {
    AppServices.shared.settings.profiles.map { ProfileEntity(id: $0.id, name: $0.name) }
  }

  func entities(for identifiers: [UUID]) async throws -> [ProfileEntity] {
    await all().filter { identifiers.contains($0.id) }
  }

  func suggestedEntities() async throws -> [ProfileEntity] {
    await all()
  }
}

// MARK: - Jacket intents

struct SignalJacketIntent: AppIntent {
  static var title: LocalizedStringResource = "Signal My Jacket"
  static var description = IntentDescription(
    "Play a vibration and light signature on your Jacquard sleeve. Use it in a Shortcuts automation (e.g. a message from someone special) to bring back jacket Alerts.")
  static var openAppWhenRun = false

  @Parameter(title: "Signal", default: SignalOption.nudge) var signal: SignalOption

  static var parameterSummary: some ParameterSummary { Summary("Send \(\.$signal) to my jacket") }

  @MainActor
  func perform() async throws -> some IntentResult {
    try await connectedServices().tag.signal(signal.signal)
    return .result()
  }
}

struct BuzzSleeveIntent: AppIntent {
  static var title: LocalizedStringResource = "Buzz Sleeve"
  static var description = IntentDescription("Vibrate the sleeve a number of times.")
  static var openAppWhenRun = false

  @Parameter(title: "Times", default: 1, inclusiveRange: (1, 6)) var times: Int
  @Parameter(title: "Long buzz", default: false) var long: Bool

  static var parameterSummary: some ParameterSummary {
    Summary("Buzz sleeve \(\.$times) times") { \.$long }
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    let tag = try await connectedServices().tag
    let note: HapticNote = long ? .long : .tap
    tag.signal(
      JacketSignal(
        id: "buzz", name: "Buzz", summary: "", haptics: Array(repeating: note, count: times),
        light: nil))
    return .result()
  }
}

struct FlashLightIntent: AppIntent {
  static var title: LocalizedStringResource = "Flash Jacket Light"
  static var description = IntentDescription("Flash the LED on your Jacquard tag.")
  static var openAppWhenRun = false

  @Parameter(title: "Colour", default: .copper) var color: LightColor
  @Parameter(title: "Flashes", default: 3, inclusiveRange: (1, 20)) var count: Int

  static var parameterSummary: some ParameterSummary {
    Summary("Flash \(\.$color) \(\.$count) times")
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    let tag = try await connectedServices().tag
    tag.flash(Array(repeating: [color.rgb, .off], count: count).flatMap { $0 }, frameMs: 200)
    return .result()
  }
}

struct FindJacketIntent: AppIntent {
  static var title: LocalizedStringResource = "Find My Jacket"
  static var description = IntentDescription("Strobe the tag light and buzz the sleeve.")
  static var openAppWhenRun = false

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    try await connectedServices().tag.signal(.find)
    return .result(dialog: "Your jacket is flashing and buzzing.")
  }
}

struct GetJacketStatusIntent: AppIntent {
  static var title: LocalizedStringResource = "Get Jacket Status"
  static var description = IntentDescription(
    "Returns connection, battery and active profile — handy in automations.")
  static var openAppWhenRun = false

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    let services = AppServices.shared
    let connected = await services.tag.waitUntilConnected(timeout: 6)
    var battery: Int?
    if connected {
      battery = await withCheckedContinuation { continuation in
        services.tag.refreshBattery { continuation.resume(returning: $0) }
      }
    }
    var parts = [connected ? "Connected" : "Not connected"]
    if let battery { parts.append("\(battery)% battery") }
    parts.append("\(services.settings.activeProfile.name) profile")
    let text = parts.joined(separator: " · ")
    return .result(value: text, dialog: "\(text)")
  }
}

struct GetJacketBatteryIntent: AppIntent {
  static var title: LocalizedStringResource = "Get Jacket Battery"
  static var openAppWhenRun = false

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
    let tag = try await connectedServices().tag
    let level: Int? = await withCheckedContinuation { continuation in
      tag.refreshBattery { continuation.resume(returning: $0) }
    }
    guard let level else { throw JacketUnreachable() }
    return .result(value: level, dialog: "Your jacket is at \(level)%.")
  }
}

struct SetProfileIntent: AppIntent {
  static var title: LocalizedStringResource = "Set Gesture Profile"
  static var description = IntentDescription(
    "Switch which gestures do what — e.g. Ride when you connect to CarPlay or start a workout.")
  static var openAppWhenRun = false

  @Parameter(title: "Profile") var profile: ProfileEntity

  static var parameterSummary: some ParameterSummary { Summary("Switch to \(\.$profile)") }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    AppServices.shared.settings.activeProfileID = profile.id
    if await AppServices.shared.tag.waitUntilConnected(timeout: 3) {
      AppServices.shared.tag.signal(.shift)
    }
    return .result(dialog: "\(profile.name) profile on.")
  }
}

struct OpenSleeveCameraIntent: AppIntent {
  static var title: LocalizedStringResource = "Open Sleeve Camera"
  static var description = IntentDescription(
    "Open the camera with your sleeve as the shutter: double tap for a photo, cover for a 3s countdown photo, brush in to flip, brush out for video.")
  static var openAppWhenRun = true

  @MainActor
  func perform() async throws -> some IntentResult {
    AppServices.shared.performer.cameraRequested = true
    return .result()
  }
}

// MARK: - Podcast intents

struct PodcastControlIntent: AudioPlaybackIntent {
  static var title: LocalizedStringResource = "Control Podcast"
  static var description = IntentDescription("Legacy CuffTag player action. Use Apple Podcasts playback actions in Shortcuts instead.")
  static var isDiscoverable = false
  static var openAppWhenRun = false

  @Parameter(title: "Command", default: .playPause) var command: PodcastCommand

  static var parameterSummary: some ParameterSummary { Summary("\(\.$command) podcast") }

  @MainActor
  func perform() async throws -> some IntentResult {
    let services = AppServices.shared
    guard services.media.activeSource == .podcasts else { throw LegacyPodcastPlayerUnavailable() }
    let player = services.player
    services.media.activeSource = .podcasts
    switch command {
    case .playPause: player.togglePlayPause()
    case .play: player.play()
    case .pause: player.pause()
    case .skipForward: player.skip(by: player.skipForwardSeconds)
    case .skipBack: player.skip(by: -player.skipBackSeconds)
    case .nextEpisode: player.playNextEpisode()
    case .bookmark:
      if let episode = player.episode {
        services.podcasts.addBookmark(episode, at: player.currentTime)
      }
    }
    return .result()
  }
}

struct PlayLatestEpisodeIntent: AudioPlaybackIntent {
  static var title: LocalizedStringResource = "Play Latest Episode"
  static var description = IntentDescription(
    "Play the newest unplayed episode, optionally from a specific show.")
  static var openAppWhenRun = false
  static var isDiscoverable = false

  @Parameter(title: "Show name") var show: String?

  static var parameterSummary: some ParameterSummary { Summary("Play latest episode of \(\.$show)") }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let services = AppServices.shared
    guard services.media.activeSource == .podcasts else { throw LegacyPodcastPlayerUnavailable() }
    await services.podcasts.refreshIfStale()
    let candidates = services.podcasts.upNext.filter { episode in
      guard let show, !show.isEmpty else { return true }
      return episode.podcastTitle.localizedCaseInsensitiveContains(show)
    }
    guard let episode = candidates.first else {
      return .result(dialog: "There's nothing new to play.")
    }
    services.media.activeSource = .podcasts
    services.player.play(episode)
    return .result(dialog: "Playing \(episode.title).")
  }
}

// MARK: - Siri & Spotlight

struct JacquardShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: FindJacketIntent(),
      phrases: ["Find my jacket with \(.applicationName)", "Where's my \(.applicationName) jacket"],
      shortTitle: "Find Jacket", systemImageName: "location.magnifyingglass")
    AppShortcut(
      intent: GetJacketStatusIntent(),
      phrases: ["\(.applicationName) status", "How's my \(.applicationName) jacket"],
      shortTitle: "Jacket Status", systemImageName: "battery.75percent")
    AppShortcut(
      intent: SignalJacketIntent(),
      phrases: ["Nudge my \(.applicationName) jacket", "Signal my jacket with \(.applicationName)"],
      shortTitle: "Signal Jacket", systemImageName: "hand.tap.fill")
    AppShortcut(
      intent: OpenSleeveCameraIntent(),
      phrases: ["Open \(.applicationName) camera", "Take a photo with \(.applicationName)"],
      shortTitle: "Sleeve Camera", systemImageName: "camera.fill")
    AppShortcut(
      intent: SetProfileIntent(),
      phrases: ["Switch \(.applicationName) profile", "Change \(.applicationName) gestures"],
      shortTitle: "Set Profile", systemImageName: "person.2.crop.square.stack.fill")
  }
}
