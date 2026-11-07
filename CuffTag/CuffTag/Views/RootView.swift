import SwiftUI

struct RootView: View {
  @EnvironmentObject private var tag: TagController
  @EnvironmentObject private var performer: ActionPerformer
  @ObservedObject var camera: SleeveCamera
  @AppStorage("onboarded") private var onboarded = false
  @State private var tab = Tab.jacket

  enum Tab: Hashable { case jacket, gestures, alerts, podcasts }

  var body: some View {
    Group {
      if onboarded {
        TabView(selection: $tab) {
          JacketView()
            .tabItem { Label("Jacket", systemImage: "jacket.fill") }
            .tag(Tab.jacket)
          GesturesView()
            .tabItem { Label("Gestures", systemImage: "hand.draw.fill") }
            .tag(Tab.gestures)
          AlertsView()
            .tabItem { Label("Alerts", systemImage: "bell.badge.waveform.fill") }
            .tag(Tab.alerts)
          ApplePodcastsView()
            .tabItem { Label("Podcasts", systemImage: "mic.fill") }
            .tag(Tab.podcasts)
        }
        .transition(.opacity)
      } else {
        OnboardingView { withAnimation(.easeInOut(duration: 0.6)) { onboarded = true } }
          .transition(.opacity)
      }
    }
    .tint(Theme.copperLight)
    .preferredColorScheme(.dark)
    .onAppear {
      let args = ProcessInfo.processInfo.arguments
      let forceOnboarding = args.contains("-onboarded")
        && (args.firstIndex(of: "-onboarded").map { $0 + 1 < args.count && args[$0 + 1].uppercased() == "NO" } ?? false)
      if tag.savedTagID != nil && !forceOnboarding { onboarded = true }
    }
    .onOpenURL(perform: handle)
    .alert("Shortcut needs attention", isPresented: Binding(
      get: { performer.problem != nil },
      set: { if !$0 { performer.problem = nil } }
    )) {
      Button("OK") { performer.problem = nil }
    } message: {
      Text(performer.problem ?? "")
    }
    .fullScreenCover(isPresented: $performer.cameraRequested) { [camera] in
      CameraView(camera: camera)
        .onAppear { performer.gestureOverride = { [weak camera] in camera?.handle($0) ?? false } }
        .onDisappear { performer.gestureOverride = nil }
    }
  }

  /// cufftag://signal/nudge, cufftag://find, cufftag://done (x-callback return)
  private func handle(_ url: URL) {
    guard url.scheme == "cufftag" else { return }
    switch url.host {
    case "signal":
      if let signal = JacketSignal.named(url.lastPathComponent) { tag.signal(signal) }
    case "find":
      tag.signal(.find)
    case "camera":
      performer.cameraRequested = true
    default:
      break
    }
  }
}

/// Reads the embedded provisioning profile so we can warn before a free-account build expires.
enum ProvisioningInfo {
  static let expirationDate: Date? = {
    guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
      let data = try? Data(contentsOf: url),
      let start = data.range(of: Data("<?xml".utf8)),
      let end = data.range(of: Data("</plist>".utf8)),
      let plist = try? PropertyListSerialization.propertyList(
        from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any]
    else { return nil }
    return plist["ExpirationDate"] as? Date
  }()

  static var daysLeft: Int? {
    expirationDate.map { Calendar.current.dateComponents([.day], from: .now, to: $0).day ?? 0 }
  }
}

struct ExpiryBanner: View {
  var body: some View {
    if let days = ProvisioningInfo.daysLeft, days <= 2 {
      HStack(spacing: 12) {
        Image(systemName: "hourglass").font(.title3).foregroundStyle(Theme.copperLight)
        VStack(alignment: .leading, spacing: 2) {
          Text(days <= 0 ? "This build expires today" : "This build expires in \(days) day\(days == 1 ? "" : "s")")
            .font(.subheadline.weight(.semibold))
          Text("Plug into your Mac and press Run in Xcode to renew for another week.")
            .font(.caption).foregroundStyle(Theme.muted)
        }
      }
      .stitchedCard(padding: 14, tint: Theme.copperLight)
    }
  }
}
