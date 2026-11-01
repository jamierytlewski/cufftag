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

    // Denim cuff body.
    let cuffPath = Path(roundedRect: cuff.insetBy(dx: 2, dy: 2), cornerRadius: 28)
    context.fill(
      cuffPath,
      with: .linearGradient(
        Gradient(colors: [Theme.denimBottom.opacity(0.9), Theme.denimTop]),
        startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
    context.stroke(
      Path(roundedRect: cuff.insetBy(dx: 9, dy: 9), cornerRadius: 22),
      with: .color(Theme.copper.opacity(0.55)), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))

    let elapsed = lastGesture.map { now.timeIntervalSince($0.date) } ?? 99
    let gesture = lastGesture?.gesture
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
      let glowWidth = 2 + 7 * energy
      context.stroke(
        path, with: .color(color.opacity(0.35 * energy)), style: StrokeStyle(lineWidth: glowWidth, lineCap: .round))
      context.stroke(
        path,
        with: .color(Theme.thread.blend(toward: color, energy)),
        style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
    }

    // Rivets at the cuff corners.
    for point in [CGPoint(x: 18, y: 18), CGPoint(x: size.width - 18, y: 18),
                  CGPoint(x: 18, y: size.height - 18), CGPoint(x: size.width - 18, y: size.height - 18)] {
      let rect = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
      context.fill(Path(ellipseIn: rect), with: .radialGradient(
        Gradient(colors: [Theme.copperLight, Theme.copper]), center: CGPoint(x: rect.minX + 3.5, y: rect.minY + 3),
        startRadius: 0, endRadius: 7))
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
      onGesture(recognizer.direction == .left ? .brushIn : .brushOut)
    }

    @objc func doubleTap() { onGesture(.doubleTap) }

    @objc func cover(_ recognizer: UILongPressGestureRecognizer) {
      if recognizer.state == .began { onGesture(.shortCover) }
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
