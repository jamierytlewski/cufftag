import SwiftUI

struct JacketView: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @EnvironmentObject private var tag: TagController
  @EnvironmentObject private var settings: GestureSettings
  @EnvironmentObject private var performer: ActionPerformer
  @State private var showSettings = false
  @State private var showPairing = false
  @State private var showGestureSchool = false
  @State private var sleevePreview: GestureEvent?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          header
          ExpiryBanner()
          hero
          if !tag.status.isConnected { connectionCard }
          profiles
          practice
          cameraCard
          quickActions
          if !tag.recentGestures.isEmpty { recent }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
      }
      .scrollIndicators(.hidden)
      .background(Theme.background)
      .withMiniPlayer()
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
            .accessibilityLabel("Settings")
        }
      }
      .sheet(isPresented: $showSettings) { SettingsView() }
      .sheet(isPresented: $showPairing) { PairingSheet() }
      .fullScreenCover(isPresented: $showGestureSchool) {
        OnboardingView(startAtSchool: true) { showGestureSchool = false }
      }
      .onChange(of: tag.lastGesture?.id) { _, _ in sleevePreview = nil }
      .onAppear { tag.refreshBattery() }
    }
  }

  // MARK: Sections

  private var header: some View {
    HStack(alignment: .center) {
      VStack(alignment: .leading, spacing: 6) {
        Text(tag.gearName ?? "Your Trucker").font(Theme.title(.largeTitle)).foregroundStyle(Theme.ink)
          .accessibilityAddTraits(.isHeader)
        HStack(spacing: 8) {
          BreathingDot(color: statusColor, breathing: !tag.status.isConnected || tag.hasGear)
          Text(statusText).font(.subheadline).foregroundStyle(Theme.muted)
        }
      }
      Spacer()
      BatteryRing(level: tag.batteryLevel, charging: tag.isCharging)
    }
    .padding(.top, 8)
  }

  private var statusText: String {
    if tag.status.isConnected {
      return tag.hasGear ? "Connected · \(settings.activeProfile.name)" : "Tag connected — snap it into your cuff"
    }
    return tag.status.label
  }

  private var statusColor: Color {
    switch tag.status {
    case .connected: return tag.hasGear ? .green : .orange
    case .connecting: return Theme.glow
    default: return .red
    }
  }

  private var hero: some View {
    VStack(spacing: 10) {
      ZStack(alignment: .bottom) {
        LivingSleeve(
          lastGesture: sleevePreview ?? tag.lastGesture, connected: tag.status.isConnected && tag.hasGear,
          shiftArmed: sleevePreview == nil && performer.shiftArmed,
          onPreview: { sleevePreview = GestureEvent(gesture: $0, date: .now, source: .screen) })
          .frame(height: 240)
          .accessibilityIdentifier("jacket-sleeve")
        if sleevePreview == nil {
          ActionToast(performed: performer.lastPerformed, shiftArmed: performer.shiftArmed)
            .padding(.bottom, 26).allowsHitTesting(false)
        }
      }
      .shadow(color: Theme.glow.opacity(tag.status.isConnected ? 0.15 : 0), radius: 30)
      if let sleevePreview {
        Text("Preview: \(sleevePreview.gesture.friendlyName)")
          .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.glow)
          .accessibilityIdentifier("sleeve-preview-feedback")
      }
      Text("Swipe the image, double tap, or touch and hold for Cover. Image previews don't run actions.")
        .font(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
    }
  }

  @ViewBuilder
  private var connectionCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      switch tag.status {
      case .notPaired:
        Text("No tag paired").font(.headline)
        Text("Hold the button on your tag for 4 seconds until the light pulses, then pair it.")
          .font(.subheadline).foregroundStyle(Theme.muted)
        Button("Pair your tag") { showPairing = true }.buttonStyle(CopperButtonStyle())
      case .bluetoothUnavailable(let reason):
        Label(reason, systemImage: "antenna.radiowaves.left.and.right.slash").font(.headline)
      default:
        Text("Looking for your jacket").font(.headline)
        Text("Make sure the tag is charged and snapped into your left cuff. Jacquard reconnects automatically — even in the background.")
          .font(.subheadline).foregroundStyle(Theme.muted)
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))) {
          Button("Try again") { tag.reconnectSavedTag() }.buttonStyle(CopperButtonStyle(prominent: false))
          Button("Pair again") { showPairing = true }.buttonStyle(CopperButtonStyle(prominent: false))
        }
      }
    }
    .stitchedCard()
  }

  private var profiles: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Profile").sectionLabel()
      ScrollView(.horizontal) {
        HStack(spacing: 10) {
          ForEach(settings.profiles) { profile in
            let active = profile.id == settings.activeProfileID
            Button {
              withAnimation(reduceMotion ? nil : .spring) { settings.activeProfileID = profile.id }
              tag.signal(.shift)
            } label: {
              ProfileChip(profile: profile, selected: active)
            }
            .buttonStyle(.plain)
          }
        }
      }
      .scrollIndicators(.hidden)
    }
  }

  private var practice: some View {
    VStack(alignment: .leading, spacing: 10) {
      (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())) {
        Text("On your sleeve").sectionLabel()
        if !typeSize.isAccessibilitySize { Spacer() }
        if settings.coverIsShift {
          Text("Cover = shift").font(.caption2.weight(.bold)).foregroundStyle(Theme.shift)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().stroke(Theme.shift.opacity(0.6)))
        }
      }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
        ForEach(JQGesture.jacketGestures) { gesture in
          Button { tag.simulate(gesture) } label: {
            GestureChip(gesture: gesture, action: settings.action(for: gesture))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Try \(gesture.friendlyName)")
          .accessibilityValue(settings.action(for: gesture).kind.title)
        }
      }
      Text("Tap a tile to try it without the jacket.").font(.caption).foregroundStyle(Theme.muted)
      Button { showGestureSchool = true } label: {
        Label("Gesture school", systemImage: "arrow.counterclockwise")
          .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
      }
    }
  }

  private var cameraCard: some View {
    Button { performer.cameraRequested = true } label: {
      HStack(spacing: 14) {
        ZStack {
          Circle().fill(Theme.copper.opacity(0.2))
          Image(systemName: "camera.fill").font(.title3).foregroundStyle(Theme.copperLight)
        }
        .frame(width: 48, height: 48)
        VStack(alignment: .leading, spacing: 3) {
          Text("Sleeve Camera").font(.headline).foregroundStyle(Theme.ink)
          Text("Double tap to shoot · brush in to flip · brush out for video · cover for timer")
            .font(.caption).foregroundStyle(Theme.muted)
        }
        Spacer()
        Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
      }
      .stitchedCard(padding: 14)
    }
    .buttonStyle(.plain)
  }

  private var quickActions: some View {
    (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))) {
      QuickAction(title: "Find jacket", symbol: "location.magnifyingglass") { tag.signal(.find) }
      QuickAction(title: "Say hello", symbol: "hand.wave.fill") { tag.signal(.hello) }
      QuickAction(title: "Battery", symbol: "battery.75percent") {
        performer.perform(.init(kind: .speakBattery))
      }
    }
    .disabled(!tag.status.isConnected)
    .opacity(tag.status.isConnected ? 1 : 0.5)
  }

  private var recent: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Recently").sectionLabel()
      VStack(spacing: 0) {
        ForEach(tag.recentGestures.prefix(6)) { event in
          HStack {
            Image(systemName: event.gesture.symbol).frame(width: 28).foregroundStyle(Theme.glow)
            Text(event.gesture.friendlyName)
            if event.source == .screen {
              Text("On-screen").font(.caption2).foregroundStyle(Theme.muted)
            }
            Spacer()
            Text(event.date, style: .relative).font(.caption).foregroundStyle(Theme.muted)
          }
          .padding(.vertical, 9)
          if event.id != tag.recentGestures.prefix(6).last?.id { Divider().opacity(0.3) }
        }
      }
      .stitchedCard(padding: 14)
    }
  }
}

struct GestureChip: View {
  let gesture: JQGesture
  let action: GestureAction

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: gesture.symbol)
        .font(.title3).foregroundStyle(Theme.glow).frame(width: 30)
      VStack(alignment: .leading, spacing: 2) {
        Text(gesture.friendlyName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
        Text(action.kind.title).font(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08)))
  }
}

struct QuickAction: View {
  let title: String
  let symbol: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 8) {
        Image(systemName: symbol).font(.title2).foregroundStyle(Theme.copperLight)
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.ink)
      }
      .frame(maxWidth: .infinity).padding(.vertical, 16)
      .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.06)))
    }
    .buttonStyle(.plain)
  }
}

/// "Brush in → Skip 30s" pill that floats over the sleeve after each gesture.
struct ActionToast: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var performed: PerformedAction?
  var shiftArmed: Bool
  @State private var visible = false

  var body: some View {
    Group {
      if shiftArmed {
        pill(symbol: "command", text: "Shift — now tap or brush", color: Theme.shift)
      } else if visible, let performed {
        pill(
          symbol: performed.action.kind.systemImage,
          text: [performed.shifted ? "Cover + " : "", performed.gesture?.friendlyName ?? "", performed.gesture == nil ? "" : " → ", performed.action.kind.title].joined(),
          color: Theme.glow)
      }
    }
    .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.35), value: visible)
    .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.35), value: shiftArmed)
    .task(id: performed) {
      guard performed != nil else { return }
      visible = true
      try? await Task.sleep(for: .seconds(2.2))
      if !Task.isCancelled { visible = false }
    }
  }

  private func pill(symbol: String, text: String, color: Color) -> some View {
    Label(text, systemImage: symbol)
      .font(.footnote.weight(.semibold))
      .padding(.horizontal, 14).padding(.vertical, 8)
      .background(.ultraThinMaterial, in: Capsule())
      .overlay(Capsule().stroke(color.opacity(0.6)))
      .foregroundStyle(Theme.ink)
      .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
  }
}
