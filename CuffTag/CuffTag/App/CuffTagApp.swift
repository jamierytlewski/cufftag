import SwiftUI
import UserNotifications

/// Long-lived services. Created at launch so CoreBluetooth state restoration works when iOS
/// relaunches the app in the background.
@MainActor
final class AppServices {
  static let shared = AppServices()

  let settings = GestureSettings()
  let podcasts = PodcastStore()
  let volume = VolumeController()
  let tag = TagController()
  let player: PodcastPlayer
  let media: MediaRouter
  let speech: SpeechAnnouncer
  let performer: ActionPerformer
  let finder: PhoneFinder
  let camera: SleeveCamera

  private init() {
    player = PodcastPlayer(store: podcasts)
    media = MediaRouter(player: player)
    speech = SpeechAnnouncer(player: player)
    finder = PhoneFinder(volume: volume, player: player)
    camera = SleeveCamera(tag: tag)
    performer = ActionPerformer(
      settings: settings, media: media, speech: speech, volume: volume, tag: tag,
      podcasts: podcasts, finder: finder)

    tag.onGesture = { [performer] gesture in performer.handle(gesture) }
  }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    MainActor.assumeIsolated { _ = AppServices.shared }
    UNUserNotificationCenter.current().delegate = self
    return true
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    guard let string = response.notification.request.content.userInfo["shortcutURL"] as? String,
      let url = URL(string: string)
    else { return }
    await AppServices.shared.performer.openShortcut(url)
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }
}

@main
struct CuffTagApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @Environment(\.scenePhase) private var scenePhase

  private let services = AppServices.shared

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(services.tag)
        .environmentObject(services.settings)
        .environmentObject(services.podcasts)
        .environmentObject(services.player)
        .environmentObject(services.media)
        .environmentObject(services.performer)
        .environmentObject(services.finder)
        .environmentObject(services.camera)
        .environment(\.volumeController, services.volume)
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { services.tag.reconnectSavedTag() }
    }
  }
}

private struct VolumeControllerKey: EnvironmentKey {
  static let defaultValue: VolumeController? = nil
}

extension EnvironmentValues {
  var volumeController: VolumeController? {
    get { self[VolumeControllerKey.self] }
    set { self[VolumeControllerKey.self] = newValue }
  }
}
