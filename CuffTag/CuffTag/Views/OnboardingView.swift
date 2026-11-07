import SwiftUI

struct GestureDemoState {
  enum Step: Int { case welcome, pairing, school, finished }

  private(set) var step: Step
  private(set) var learned: Set<Int> = []
  private(set) var lastGesture: GestureEvent?

  init(step: Step = .welcome) { self.step = step }

  mutating func receive(_ event: GestureEvent) {
    guard step == .welcome || step == .school,
      JQGesture.jacketGestures.contains(event.gesture) else { return }
    lastGesture = event
    if step == .school { learned.insert(event.gesture.rawValue) }
  }

  mutating func next() {
    switch step {
    case .welcome: step = .pairing
    case .pairing: step = .school
    case .school: step = .finished
    case .finished: break
    }
    lastGesture = nil
  }

  mutating func startOver() { self = Self() }
  mutating func retry() { self = Self(step: .school) }
}

struct OnboardingView: View {
  var onFinish: () -> Void
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @EnvironmentObject private var tag: TagController
  @EnvironmentObject private var performer: ActionPerformer
  @State private var demo: GestureDemoState

  init(startAtSchool: Bool = false, onFinish: @escaping () -> Void) {
    self.onFinish = onFinish
    _demo = State(initialValue: GestureDemoState(step: startAtSchool ? .school : .welcome))
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        HStack(spacing: 6) {
          ForEach(0..<4) { index in
            Capsule().fill(index <= demo.step.rawValue ? Theme.copper : Color.white.opacity(0.15))
              .frame(width: index == demo.step.rawValue ? 22 : 8, height: 6)
          }
        }
        .animation(reduceMotion ? nil : .spring, value: demo.step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Getting started")
        .accessibilityValue("Step \(demo.step.rawValue + 1) of 4")
        Spacer()
        Button("Start over") { demo.startOver() }
          .font(.subheadline).foregroundStyle(Theme.copperLight)
          .frame(minWidth: 44, minHeight: 44)
          .accessibilityHint("Resets only this demo, not your pairing or gesture settings.")
        if demo.step != .finished {
          Button("Skip") { finish() }.foregroundStyle(Theme.muted)
            .frame(minWidth: 44, minHeight: 44)
        }
      }
      .padding(.horizontal, 24).padding(.top, 12)

      GeometryReader { geometry in
        ScrollView {
          Group {
            switch demo.step {
            case .welcome: welcome
            case .pairing: pair
            case .school: school
            case .finished: done
            }
          }
          .frame(maxWidth: .infinity, minHeight: geometry.size.height)
        }
        .scrollIndicators(.hidden)
        .id(demo.step)
        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
      }
    }
    .background(Theme.background)
    .onChange(of: tag.lastGesture?.id) { _, _ in
      guard let event = tag.lastGesture else { return }
      demo.receive(event)
    }
    .onAppear { performer.demoMode = true }
    .onDisappear { performer.demoMode = false }
  }

  private func next() {
    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.5)) { demo.next() }
  }

  private func finish() {
    performer.demoMode = false
    tag.celebrate()
    onFinish()
  }

  private var welcome: some View {
    VStack(spacing: 28) {
      Spacer()
      VStack(spacing: 10) {
        LivingSleeve(lastGesture: demo.lastGesture, connected: tag.status.isConnected,
                    shiftArmed: false, onPreview: preview)
          .frame(height: 240)
          .accessibilityIdentifier("demo-sleeve")
        previewInstructions
      }
      .padding(.horizontal, 24)
      VStack(spacing: 12) {
        Text("Your jacket\nremembers.").font(Theme.title(.largeTitle)).multilineTextAlignment(.center)
          .accessibilityAddTraits(.isHeader)
        Text("Google switched off the cloud. The threads in your sleeve still work. Let's wake them up — no account, no servers, just your jacket and your phone.")
          .font(.callout).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
      }
      .padding(.horizontal, 28)
      Spacer()
      Button("Begin") { next() }.buttonStyle(CopperButtonStyle()).padding(.horizontal, 24).padding(.bottom, 20)
    }
  }

  private var pair: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Find your tag").font(Theme.title()).accessibilityAddTraits(.isHeader)
      if tag.status.isConnected {
        Label("Your tag is already connected.", systemImage: "checkmark.circle.fill")
          .foregroundStyle(Theme.glow)
        Text("Keep it paired and head straight to Gesture school.")
          .font(.callout).foregroundStyle(Theme.muted)
        Button("Continue") { next() }.buttonStyle(CopperButtonStyle())
      } else {
        PairingPanel {
          tag.breathe(.copper, seconds: 3)
          next()
        }
        Button("Try without a tag") { next() }
          .buttonStyle(CopperButtonStyle(prominent: false))
      }
    }
    .padding(24)
  }

  private var school: some View {
    VStack(spacing: 22) {
      VStack(spacing: 8) {
        Text("Gesture school").font(Theme.title()).accessibilityAddTraits(.isHeader)
        Text("Try your jacket or the image below. Actions are paused while this demo is open.")
          .font(.callout).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
      }
      .padding(.top, 24).padding(.horizontal, 24)
      VStack(spacing: 10) {
        LivingSleeve(lastGesture: demo.lastGesture, connected: tag.status.isConnected && tag.hasGear,
                    shiftArmed: false, onPreview: preview)
          .frame(height: 180)
          .accessibilityIdentifier("demo-sleeve")
        previewInstructions
        if !tag.status.isConnected || !tag.hasGear {
          Text(tag.status.isConnected
               ? "Snap the tag into your cuff to try the real threads."
               : "No jacket connected. You can still try everything on screen.")
            .font(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
      }
      .padding(.horizontal, 24)
      LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
        ForEach(JQGesture.jacketGestures, id: \.rawValue) { gesture in
          let ok = demo.learned.contains(gesture.rawValue)
          Button { preview(gesture) } label: {
            VStack(spacing: 8) {
              Image(systemName: ok ? "checkmark.circle.fill" : gesture.symbol)
                .font(.title2).foregroundStyle(ok ? .green : Theme.copperLight)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
              Text(gesture.friendlyName).font(.subheadline.weight(.semibold))
              Text(gesture.hint).font(.caption2).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 110)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 18).fill(ok ? Color.green.opacity(0.12) : Color.white.opacity(0.05)))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Preview \(gesture.friendlyName)")
          .accessibilityValue(ok ? "Practiced" : "Not practiced")
          .accessibilityHint(gesture.hint)
        }
      }
      .padding(.horizontal, 24)
      HStack {
        Text("\(demo.learned.count) of \(JQGesture.jacketGestures.count) practiced")
          .font(.subheadline).foregroundStyle(Theme.muted)
          .accessibilityIdentifier("demo-progress")
        Spacer()
        Button("Try again") { demo.retry() }
          .frame(minWidth: 44, minHeight: 44)
          .accessibilityHint("Clears the practice checkmarks and the sleeve preview.")
      }
      .padding(.horizontal, 24)
      Spacer()
      Button(demo.learned.count == JQGesture.jacketGestures.count ? "Nailed it" : "Continue") { next() }
        .buttonStyle(CopperButtonStyle(prominent: demo.learned.count == JQGesture.jacketGestures.count))
        .padding(.horizontal, 24).padding(.bottom, 20)
    }
  }

  private var done: some View {
    VStack(spacing: 24) {
      Spacer()
      Image(systemName: "sparkles").font(.system(size: 56)).foregroundStyle(Theme.copperLight)
        .symbolEffect(.pulse, isActive: !reduceMotion)
        .accessibilityHidden(true)
      Text("You're threaded in.").font(Theme.title(.largeTitle))
        .multilineTextAlignment(.center).padding(.horizontal, 24)
        .accessibilityAddTraits(.isHeader)
      VStack(alignment: .leading, spacing: 14) {
        tip("hand.raised.fill", "Cover is your shift key", "Cover, then brush in or out, for volume. The initial Cover + double tap mapping says your jacket battery; saved profiles keep their mappings.")
        tip("camera.fill", "Sleeve Camera", "Prop up your phone, double tap your cuff to take the shot.")
        tip("bell.badge.fill", "Bring back Alerts", "The Alerts tab shows how to make your sleeve buzz for the people who matter.")
      }
      .stitchedCard()
      .padding(.horizontal, 24)
      Spacer()
      Button("Try gestures again") { demo.retry() }
        .frame(minHeight: 44).foregroundStyle(Theme.copperLight)
      Button("Start wearing it") { finish() }.buttonStyle(CopperButtonStyle()).padding(.horizontal, 24).padding(.bottom, 20)
    }
  }

  private func preview(_ gesture: JQGesture) {
    demo.receive(GestureEvent(gesture: gesture, date: .now, source: .screen))
  }

  private var previewInstructions: some View {
    VStack(spacing: 6) {
      if let event = demo.lastGesture {
        Text("\(event.source == .jacket ? "Jacket" : "Preview"): \(event.gesture.friendlyName)")
          .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.glow)
          .accessibilityIdentifier("demo-feedback")
      }
      Text("Swipe left or right, double tap, or touch and hold for Cover. Watch the threads respond.")
        .font(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func tip(_ symbol: String, _ title: String, _ body: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol).foregroundStyle(Theme.copper).frame(width: 24)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.subheadline.weight(.semibold))
        Text(body).font(.caption).foregroundStyle(Theme.muted)
      }
    }
  }
}
