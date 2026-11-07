import CoreGraphics
import JacquardSDK
import SwiftUI
import UIKit
import UserNotifications

/// Shared app services so the UI, background Bluetooth wake-ups and App Intents talk to the same objects.
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
    player = PodcastPlayer(store: podcasts, restorePlayback: false)
    media = MediaRouter(player: player)
    speech = SpeechAnnouncer(player: player)
    finder = PhoneFinder(volume: volume, player: player)
    camera = SleeveCamera(tag: tag)
    performer = ActionPerformer(
      settings: settings, media: media, speech: speech,
      volume: volume, tag: tag, podcasts: podcasts, finder: finder)
    tag.onGesture = { [weak performer] gesture in
      performer?.handle(gesture)
    }
    if DemoContent.isEnabled {
      DemoContent.configure(services: self)
    }
  }
}

/// Seeds realistic connected-jacket, podcast, and camera showcase state when launched with `-appStoreDemo YES`.
@MainActor
enum DemoContent {
  static var isEnabled: Bool {
    let args = ProcessInfo.processInfo.arguments
    if let idx = args.firstIndex(of: "-appStoreDemo"), idx + 1 < args.count {
      let val = args[idx + 1].lowercased()
      return val == "yes" || val == "true" || val == "1"
    }
    return args.contains("-appStoreDemo")
  }

  static func configure(services: AppServices) {
    let now = Date()
    let recent: [GestureEvent] = [
      .init(gesture: .brushIn, date: now.addingTimeInterval(-14), source: .jacket),
      .init(gesture: .doubleTap, date: now.addingTimeInterval(-95), source: .jacket),
      .init(gesture: .shortCover, date: now.addingTimeInterval(-240), source: .jacket),
      .init(gesture: .brushOut, date: now.addingTimeInterval(-510), source: .jacket),
    ]
    services.tag.enableDemoMode(
      gearName: "Levi's® Trucker Jacket",
      tagName: "Jacquard Tag 8F2A",
      firmwareVersion: "1.96.0",
      batteryLevel: 86,
      recentGestures: recent
    )

    let artIndigoURL = writeArtwork(
      filename: "demo-art-indigo.png",
      top: UIColor(red: 0.10, green: 0.16, blue: 0.36, alpha: 1),
      bottom: UIColor(red: 0.04, green: 0.07, blue: 0.16, alpha: 1),
      accent: UIColor(red: 0.50, green: 0.89, blue: 1.0, alpha: 1),
      symbol: "waveform.path.ecg",
      title: "WOVEN SIGNAL"
    )
    let coverImage = artIndigoURL.flatMap { UIImage(contentsOfFile: $0.path) }
    services.camera.enableDemoPreview(thumbnail: coverImage)
  }

  private static func writeArtwork(
    filename: String, top: UIColor, bottom: UIColor, accent: UIColor, symbol: String, title: String
  ) -> URL? {
    let size = CGSize(width: 600, height: 600)
    let renderer = UIGraphicsImageRenderer(size: size)
    let image = renderer.image { ctx in
      let cg = ctx.cgContext
      let colors = [top.cgColor, bottom.cgColor] as CFArray
      if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])
      {
        cg.drawLinearGradient(
          gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
      }

      cg.setStrokeColor(UIColor.white.withAlphaComponent(0.06).cgColor)
      cg.setLineWidth(2)
      var x: CGFloat = -size.height
      while x < size.width {
        cg.move(to: CGPoint(x: x, y: size.height))
        cg.addLine(to: CGPoint(x: x + size.height, y: 0))
        x += 18
      }
      cg.strokePath()

      let inset = CGRect(x: 28, y: 28, width: size.width - 56, height: size.height - 56)
      let border = UIBezierPath(roundedRect: inset, cornerRadius: 48)
      accent.withAlphaComponent(0.55).setStroke()
      border.lineWidth = 4
      border.setLineDash([14, 10], count: 2, phase: 0)
      border.stroke()

      cg.setFillColor(accent.withAlphaComponent(0.18).cgColor)
      cg.fillEllipse(in: CGRect(x: 170, y: 120, width: 260, height: 260))

      let config = UIImage.SymbolConfiguration(pointSize: 120, weight: .semibold)
      if let sym = UIImage(systemName: symbol, withConfiguration: config)?
        .withTintColor(accent, renderingMode: .alwaysOriginal)
      {
        let symRect = CGRect(
          x: (size.width - sym.size.width) / 2,
          y: 250 - sym.size.height / 2,
          width: sym.size.width,
          height: sym.size.height
        )
        sym.draw(in: symRect)
      }

      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = .center
      let attrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 34, weight: .bold),
        .foregroundColor: UIColor.white.withAlphaComponent(0.92),
        .kern: 3.0,
        .paragraphStyle: paragraph,
      ]
      let str = NSAttributedString(string: title, attributes: attrs)
      str.draw(in: CGRect(x: 40, y: 450, width: size.width - 80, height: 60))
    }

    let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    try? image.pngData()?.write(to: url)
    return url
  }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    _ = AppServices.shared
    return true
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let openCamera = response.notification.request.content.userInfo["openCamera"] as? Bool == true
    let urlString = response.notification.request.content.userInfo["shortcutURL"] as? String
    Task { @MainActor in
      if openCamera {
        AppServices.shared.performer.cameraRequested = true
      } else if let urlString, let url = URL(string: urlString) {
        await AppServices.shared.performer.openShortcut(url, signalOnSuccess: true)
      }
      completionHandler()
    }
  }
}

@main
struct CuffTagApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @Environment(\.scenePhase) private var scenePhase
  private var services: AppServices { .shared }

  var body: some Scene {
    WindowGroup {
      RootView(camera: services.camera)
        .environmentObject(services.tag)
        .environmentObject(services.settings)
        .environmentObject(services.performer)
        .environmentObject(services.podcasts)
        .environmentObject(services.player)
        .environmentObject(services.media)
        .environmentObject(services.finder)
        .background(HiddenVolumeView(controller: services.volume).frame(width: 0, height: 0))
        .preferredColorScheme(.dark)
        .tint(Theme.copper)
        .onChange(of: scenePhase) { _, phase in
          if phase == .active { services.tag.reconnectSavedTag() }
        }
    }
  }
}
