import SwiftUI

/// The hero: a cuff of conductive threads that lights up as you touch the real sleeve.
/// Brushes sweep a glow across the threads, double taps ripple, cover floods them.
struct LivingSleeve: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  var lastGesture: GestureEvent?
  var connected: Bool
  var shiftArmed: Bool
  var threadCount = 12
  var onPreview: ((JQGesture) -> Void)?

  var body: some View {
    if let onPreview {
      sleeve
        .overlay { SleeveTouchSurface(onGesture: onPreview).accessibilityHidden(true) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Interactive sleeve")
        .accessibilityValue(accessibilityStatus)
        .accessibilityHint("Swipe left or right, double tap, or touch and hold for Cover. Previews do not run actions.")
        .accessibilityAction(named: Text("Preview \(JQGesture.brushIn.friendlyName)")) { onPreview(.brushIn) }
        .accessibilityAction(named: Text("Preview \(JQGesture.brushOut.friendlyName)")) { onPreview(.brushOut) }
        .accessibilityAction(named: Text("Preview \(JQGesture.doubleTap.friendlyName)")) { onPreview(.doubleTap) }
        .accessibilityAction(named: Text("Preview \(JQGesture.shortCover.friendlyName)")) { onPreview(.shortCover) }
    } else {
      sleeve
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleeve")
        .accessibilityValue(accessibilityStatus)
    }
  }

  private var accessibilityStatus: String {
    if shiftArmed { return "Cover shift ready" }
    if let lastGesture {
      return "\(lastGesture.source == .jacket ? "Jacket" : "On-screen"): \(lastGesture.gesture.friendlyName)"
    }
    return connected ? "Connected" : "Disconnected"
  }

  private var sleeve: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) { timeline in
      Canvas { context, size in
        draw(in: &context, size: size, now: timeline.date)
      }
    }
  }

  private func draw(in context: inout GraphicsContext, size: CGSize, now: Date) {
    let t = reduceMotion ? 0 : now.timeIntervalSinceReferenceDate
    let cuff = CGRect(x: 0, y: 0, width: size.width, height: size.height)
    let cuffRect = cuff.insetBy(dx: 2, dy: 2)
    let cuffPath = Path(roundedRect: cuffRect, cornerRadius: 28)

    // Denim cuff body with rich indigo gradient.
    context.fill(
      cuffPath,
      with: .linearGradient(
        Gradient(colors: [
          Theme.denimBottom.opacity(0.95),
          Theme.denimTop,
          Color(red: 0.035, green: 0.055, blue: 0.13),
        ]),
        startPoint: .zero,
        endPoint: CGPoint(x: 0, y: size.height)
      )
    )

    // Clipped interior twill texture and ambient glow.
    var innerContext = context
    innerContext.clip(to: cuffPath)

    var twillPath = Path()
    let twillStep: CGFloat = 6
    var tx: CGFloat = -size.height
    while tx < size.width {
      twillPath.move(to: CGPoint(x: tx, y: size.height))
      twillPath.addLine(to: CGPoint(x: tx + size.height, y: 0))
      tx += twillStep
    }
    innerContext.stroke(twillPath, with: .color(.white.opacity(0.045)), lineWidth: 0.7)

    let activeColor = shiftArmed ? Theme.shift : Theme.glow
    let elapsed = lastGesture.map { now.timeIntervalSince($0.date) } ?? 99
    let gesture = lastGesture?.gesture
    let gestureFade = fade(elapsed, 1.2)

    if connected || shiftArmed || gestureFade > 0 {
      let bloomOpacity = max(connected ? 0.10 : 0.0, gestureFade * 0.22, shiftArmed ? 0.20 : 0)
      let bloomCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
      innerContext.fill(
        cuffPath,
        with: .radialGradient(
          Gradient(colors: [activeColor.opacity(bloomOpacity), .clear]),
          center: bloomCenter,
          startRadius: 10,
          endRadius: max(size.width, size.height) * 0.65
        )
      )
    }

    // Outer specular seam & inner copper chain-stitching.
    context.stroke(
      cuffPath,
      with: .linearGradient(
        Gradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.05)]),
        startPoint: .zero,
        endPoint: CGPoint(x: 0, y: size.height)
      ),
      lineWidth: 1.2
    )
    context.stroke(
      Path(roundedRect: cuff.insetBy(dx: 9, dy: 9), cornerRadius: 22),
      with: .color(Theme.copper.opacity(0.6)),
      style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])
    )
    context.stroke(
      Path(roundedRect: cuff.insetBy(dx: 13, dy: 13), cornerRadius: 19),
      with: .color(Theme.copper.opacity(0.28)),
      style: StrokeStyle(lineWidth: 0.9, dash: [6, 5], dashPhase: 3)
    )

    let margin: CGFloat = 34
    let spacing = (size.width - margin * 2) / CGFloat(threadCount - 1)
    let idleBreath = connected ? 0.18 + 0.1 * sin(t * 1.6) : 0.08

    for i in 0..<threadCount {
      let x = margin + CGFloat(i) * spacing
      let u = Double(i) / Double(threadCount - 1)
      var energy = idleBreath

      switch gesture {
      case .brushIn?, .brushOut?:
        let head = elapsed / 0.55
        let pos = gesture == .brushIn ? 1 - u : u
        let d = head - pos
        if d > -0.15 && d < 0.6 { energy = max(energy, exp(-pow(d * 4.5, 2)) * fade(elapsed, 1.1)) }
      case .doubleTap?:
        let center = 0.5
        for pulse in 0..<2 {
          let r = (elapsed - Double(pulse) * 0.18) * 1.6
          let d = abs(abs(u - center) - r)
          if r > 0 { energy = max(energy, exp(-pow(d * 8, 2)) * fade(elapsed, 0.9)) }
        }
      case .shortCover?:
        energy = max(energy, 0.95 * fade(elapsed, 1.4))
      case .brushUp?, .brushDown?:
        energy = max(energy, 0.7 * fade(elapsed, 0.8))
      default:
        break
      }
      if shiftArmed { energy = max(energy, 0.45 + 0.25 * sin(t * 9)) }
      if reduceMotion { energy = shiftArmed ? 0.7 : (lastGesture == nil ? idleBreath : 0.45) }

      // Each thread: a gentle weave wave running the height of the cuff.
      var path = Path()
      let top: CGFloat = 22
      let bottom = size.height - 22
      path.move(to: CGPoint(x: x, y: top))
      var y = top
      while y <= bottom {
        let phase = Double(y) / 18 + t * (connected ? 1.2 : 0.3) + Double(i) * 0.6
        let vertical: Double
        if gesture == .brushUp || gesture == .brushDown {
          let head = (gesture == .brushUp ? 1 - elapsed / 0.6 : elapsed / 0.6)
          vertical = exp(-pow((Double((y - top) / (bottom - top)) - head) * 5, 2)) * fade(elapsed, 0.9)
        } else {
          vertical = 0
        }
        let wobble = sin(phase) * (1.2 + 2.5 * energy + 3 * vertical)
        path.addLine(to: CGPoint(x: x + wobble, y: y))
        y += 4
      }

      let color = shiftArmed ? Theme.shift : Theme.glow
      let glowWidth = 2.5 + 8 * energy
      context.stroke(
        path,
        with: .color(color.opacity(0.38 * energy)),
        style: StrokeStyle(lineWidth: glowWidth, lineCap: .round)
      )
      context.stroke(
        path,
        with: .color(Theme.thread.blend(toward: color, energy)),
        style: StrokeStyle(lineWidth: 1.7 + 0.6 * energy, lineCap: .round)
      )

      // Conductive copper-core filament highlight when energized.
      if energy > 0.32 {
        context.stroke(
          path,
          with: .color( Color.white.opacity((energy - 0.32) * 0.65) ),
          style: StrokeStyle(lineWidth: 0.8, lineCap: .round, dash: [3, 9], dashPhase: CGFloat(t * 18 + Double(i) * 3))
        )
      }
    }

    // Stamped copper rivets at the cuff corners.
    for point in [
      CGPoint(x: 18, y: 18), CGPoint(x: size.width - 18, y: 18),
      CGPoint(x: 18, y: size.height - 18), CGPoint(x: size.width - 18, y: size.height - 18),
    ] {
      let shadowRect = CGRect(x: point.x - 5.5, y: point.y - 4.5, width: 11, height: 11)
      context.fill(Path(ellipseIn: shadowRect), with: .color(.black.opacity(0.45)))

      let rect = CGRect(x: point.x - 5.5, y: point.y - 5.5, width: 11, height: 11)
      context.fill(
        Path(ellipseIn: rect),
        with: .radialGradient(
          Gradient(colors: [Theme.copperLight, Theme.copper, Theme.copper.opacity(0.75)]),
          center: CGPoint(x: rect.minX + 3.5, y: rect.minY + 3.5),
          startRadius: 0,
          endRadius: 8
        )
      )
      context.stroke(Path(ellipseIn: rect), with: .color(.black.opacity(0.35)), lineWidth: 0.6)
      let innerPin = CGRect(x: point.x - 1.8, y: point.y - 1.8, width: 3.6, height: 3.6)
      context.fill(Path(ellipseIn: innerPin), with: .color(Theme.copperLight))
    }
  }

  private func fade(_ elapsed: Double, _ length: Double) -> Double {
    max(0, 1 - elapsed / length)
  }
}

/// Directional recognizers let vertical drags keep scrolling the surrounding page.
struct SleeveTouchSurface: UIViewRepresentable {
  var onGesture: (JQGesture) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(onGesture: onGesture) }

  func makeUIView(context: Context) -> UIView {
    let view = UIView()
    view.backgroundColor = .clear
    for direction: UISwipeGestureRecognizer.Direction in [.left, .right] {
      let swipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.swipe(_:)))
      swipe.direction = direction
      view.addGestureRecognizer(swipe)
    }
    let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap))
    tap.numberOfTapsRequired = 2
    view.addGestureRecognizer(tap)
    let cover = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.cover(_:)))
    cover.minimumPressDuration = 0.45
    cover.allowableMovement = 18
    view.addGestureRecognizer(cover)
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    context.coordinator.onGesture = onGesture
  }

  final class Coordinator: NSObject {
    var onGesture: (JQGesture) -> Void

    init(onGesture: @escaping (JQGesture) -> Void) { self.onGesture = onGesture }

    @objc func swipe(_ recognizer: UISwipeGestureRecognizer) {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      onGesture(recognizer.direction == .left ? .brushIn : .brushOut)
    }

    @objc func doubleTap() {
      UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
      onGesture(.doubleTap)
    }

    @objc func cover(_ recognizer: UILongPressGestureRecognizer) {
      if recognizer.state == .began {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onGesture(.shortCover)
      }
    }
  }
}

extension Color {
  func blend(toward other: Color, _ amount: Double) -> Color {
    let a = UIColor(self).rgba, b = UIColor(other).rgba
    let k = min(max(amount, 0), 1)
    return Color(
      red: a.0 + (b.0 - a.0) * k, green: a.1 + (b.1 - a.1) * k, blue: a.2 + (b.2 - a.2) * k)
  }
}

extension UIColor {
  fileprivate var rgba: (Double, Double, Double) {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    getRed(&r, green: &g, blue: &b, alpha: &a)
    return (Double(r), Double(g), Double(b))
  }
}
