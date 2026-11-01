import SwiftUI

/// "Indigo Thread": raw denim, copper rivets and a cyan conductive-thread glow.
enum Theme {
  static let denimTop = Color(red: 0.055, green: 0.086, blue: 0.188)
  static let denimBottom = Color(red: 0.106, green: 0.165, blue: 0.333)
  static let copper = Color(red: 0.784, green: 0.455, blue: 0.227)
  static let copperLight = Color(red: 0.93, green: 0.64, blue: 0.40)
  static let glow = Color(red: 0.498, green: 0.89, blue: 1.0)
  static let shift = Color(red: 0.70, green: 0.50, blue: 1.0)
  static let thread = Color(red: 0.36, green: 0.47, blue: 0.75)
  static let ink = Color.white.opacity(0.92)
  static let muted = Color.white.opacity(0.58)

  static var background: some View {
    ZStack {
      LinearGradient(colors: [denimTop, denimBottom], startPoint: .top, endPoint: .bottom)
      DenimTwill().opacity(0.06)
    }
    .ignoresSafeArea()
  }

  static func title(_ style: Font.TextStyle = .title) -> Font {
    .system(style, design: .serif, weight: .semibold)
  }

  static func number(_ style: Font.TextStyle) -> Font {
    .system(style, design: .rounded, weight: .semibold).monospacedDigit()
  }
}

/// Diagonal twill weave texture.
struct DenimTwill: View {
  var body: some View {
    Canvas { context, size in
      var path = Path()
      let step: CGFloat = 5
      var x: CGFloat = -size.height
      while x < size.width {
        path.move(to: CGPoint(x: x, y: size.height))
        path.addLine(to: CGPoint(x: x + size.height, y: 0))
        x += step
      }
      context.stroke(path, with: .color(.white), lineWidth: 0.6)
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

/// Frosted card with a stitched (dashed copper) inner border.
struct StitchedCard: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  var padding: CGFloat = 18
  var tint: Color = Theme.copper

  func body(content: Content) -> some View {
    content
      .padding(padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        reduceTransparency ? AnyShapeStyle(Theme.denimTop) : AnyShapeStyle(.ultraThinMaterial.opacity(0.55)),
        in: RoundedRectangle(cornerRadius: 24))
      .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 24))
      .overlay(
        RoundedRectangle(cornerRadius: 19)
          .inset(by: 5)
          .stroke(tint.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
      )
      .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.06)))
  }
}

extension View {
  func stitchedCard(padding: CGFloat = 18, tint: Color = Theme.copper) -> some View {
    modifier(StitchedCard(padding: padding, tint: tint))
  }

  func sectionLabel() -> some View {
    self.font(.footnote.weight(.semibold)).textCase(.uppercase).tracking(1.2)
      .foregroundStyle(Theme.muted)
      .accessibilityAddTraits(.isHeader)
  }
}

/// Copper rivet, used as a bullet / badge.
struct Rivet: View {
  var size: CGFloat = 12
  var body: some View {
    Circle()
      .fill(
        RadialGradient(
          colors: [Theme.copperLight, Theme.copper, Theme.copper.opacity(0.6)],
          center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.6)
      )
      .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 0.5))
      .frame(width: size, height: size)
      .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
      .accessibilityHidden(true)
  }
}

struct CopperButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var prominent = true
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .padding(.vertical, 14)
      .padding(.horizontal, 22)
      .frame(maxWidth: .infinity, minHeight: 44)
      .multilineTextAlignment(.center)
      .foregroundStyle(prominent ? Color.black.opacity(0.85) : Theme.ink)
      .background(
        Capsule().fill(
          prominent
            ? AnyShapeStyle(
              LinearGradient(
                colors: [Theme.copperLight, Theme.copper], startPoint: .top, endPoint: .bottom))
            : AnyShapeStyle(Color.white.opacity(0.08)))
      )
      .overlay(Capsule().stroke(Color.white.opacity(prominent ? 0.25 : 0.12)))
      .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
      .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.25), value: configuration.isPressed)
  }
}

struct ProfileChip: View {
  let profile: GestureProfile
  let selected: Bool

  var body: some View {
    Label(profile.name, systemImage: profile.symbol)
      .font(.subheadline.weight(.semibold))
      .padding(.horizontal, 16).padding(.vertical, 10)
      .frame(minHeight: 44)
      .foregroundStyle(selected ? Color.black.opacity(0.85) : Theme.ink)
      .background(Capsule().fill(selected ? Theme.copper : Color.white.opacity(0.07)))
      .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// Small breathing status dot.
struct BreathingDot: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  var color: Color
  var breathing = true
  @State private var phase = false
  private var animating: Bool { breathing && !reduceMotion && scenePhase == .active }

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: 9, height: 9)
      .background(
        Circle().fill(color.opacity(0.45)).scaleEffect(phase ? 2.4 : 1)
          .opacity(phase ? 0 : 0.8)
      )
      .animation(animating ? .easeOut(duration: 1.8).repeatForever(autoreverses: false) : nil, value: phase)
      .onChange(of: animating, initial: true) { _, value in phase = value }
      .accessibilityHidden(true)
  }
}

struct BatteryRing: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var level: Int?
  var charging: Bool
  var size: CGFloat = 54

  private var fraction: Double { min(max(Double(level ?? 0) / 100, 0), 1) }
  private var color: Color {
    guard let level else { return Theme.muted }
    if level <= 15 { return .red }
    if level <= 30 { return .orange }
    return Theme.glow
  }

  var body: some View {
    ZStack {
      Circle().stroke(Color.white.opacity(0.1), lineWidth: 5)
      Circle()
        .trim(from: 0, to: fraction)
        .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .shadow(color: color.opacity(0.6), radius: 4)
      VStack(spacing: 0) {
        if charging {
          Image(systemName: "bolt.fill").font(.system(size: 10)).foregroundStyle(Theme.glow)
        }
        Text(level.map { "\($0)" } ?? "–")
          .font(.system(size: size * 0.3, weight: .semibold, design: .rounded).monospacedDigit())
      }
    }
    .frame(width: size, height: size)
    .animation(reduceMotion ? nil : .spring, value: level)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Jacket battery")
    .accessibilityValue(level.map { "\($0) percent\(charging ? ", charging" : "")" } ?? "Unavailable")
  }
}

/// Embeds the hidden MPVolumeView so sleeve volume gestures work.
struct HiddenVolumeView: UIViewRepresentable {
  let controller: VolumeController
  func makeUIView(context: Context) -> UIView {
    let container = UIView(frame: .zero)
    container.isUserInteractionEnabled = false
    container.addSubview(controller.volumeView)
    return container
  }
  func updateUIView(_ uiView: UIView, context: Context) {}
}
