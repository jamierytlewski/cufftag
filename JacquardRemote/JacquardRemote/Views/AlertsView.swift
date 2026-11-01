import SwiftUI

struct AlertRecipe: Identifiable {
  let id = UUID()
  let title: String
  let symbol: String
  let trigger: String
  let steps: [String]
  let signal: JacketSignal?
}

struct AlertsView: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @EnvironmentObject private var tag: TagController
  @State private var expanded: UUID?

  static let recipes: [AlertRecipe] = [
    .init(
      title: "Someone special texts you", symbol: "message.fill", trigger: "Message",
      steps: [
        "Shortcuts › Automation › New Automation › Message",
        "Choose the sender (and optionally words it contains)",
        "Pick “Run Immediately”",
        "Add the Jacquard action “Signal My Jacket” › Nudge",
      ], signal: .nudge),
    .init(
      title: "Important email arrives", symbol: "envelope.badge.fill", trigger: "Email",
      steps: [
        "Shortcuts › Automation › New Automation › Email",
        "Choose the sender or subject",
        "Run Immediately › “Signal My Jacket” › Alert",
      ], signal: .alert),
    .init(
      title: "Arriving or leaving a place", symbol: "location.fill", trigger: "Arrive / Leave",
      steps: [
        "Shortcuts › Automation › New Automation › Arrive (or Leave)",
        "Pick the place, Run Immediately",
        "Add “Signal My Jacket” › Hello — or “Set Gesture Profile”",
      ], signal: .hello),
    .init(
      title: "Ride mode on your bike or in the car", symbol: "bicycle", trigger: "CarPlay / Bluetooth",
      steps: [
        "Automation › CarPlay (or Bluetooth › your headphones)",
        "Run Immediately › “Set Gesture Profile” › Ride",
        "Add a second automation on disconnect › Everyday",
      ], signal: .shift),
    .init(
      title: "Focus turns on", symbol: "moon.fill", trigger: "Focus",
      steps: [
        "Automation › Focus › choose a Focus › When Turning On",
        "“Set Gesture Profile” › Focus",
      ], signal: .shift),
    .init(
      title: "Morning battery check", symbol: "battery.25percent", trigger: "Time of Day",
      steps: [
        "Automation › Time of Day › 7:30, Run Immediately",
        "“Get Jacket Battery”",
        "If Battery is less than 25 › Show Notification “Charge your jacket tag”",
      ], signal: nil),
    .init(
      title: "Timer or reminder done", symbol: "timer", trigger: "Alarm",
      steps: [
        "Automation › Alarm › Is Stopped (or use a Shortcut with Wait)",
        "“Signal My Jacket” › Done",
      ], signal: .confirm),
  ]

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          intro
          VStack(alignment: .leading, spacing: 10) {
            Text("Recipes").sectionLabel()
            ForEach(Self.recipes) { recipe in recipeCard(recipe) }
          }
          signals
          sleeveToShortcuts
        }
        .padding(.horizontal, 20).padding(.bottom, 30)
      }
      .scrollIndicators(.hidden)
      .background(Theme.background)
      .navigationTitle("Alerts")
      .withMiniPlayer()
    }
  }

  private var intro: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Feel what matters.").font(Theme.title(.title2))
      Text("The old Jacquard app buzzed your sleeve for the people you care about. iOS doesn't let apps read your notifications — but **Shortcuts automations** can see messages, emails, places and more, and run **Signal My Jacket** in the background.")
        .font(.callout).foregroundStyle(Theme.muted)
      Button {
        UIApplication.shared.open(URL(string: "shortcuts://")!)
      } label: {
        Label("Open Shortcuts", systemImage: "square.2.layers.3d.fill")
      }
      .buttonStyle(CopperButtonStyle())
    }
    .stitchedCard()
  }

  private func recipeCard(_ recipe: AlertRecipe) -> some View {
    let open = expanded == recipe.id
    return VStack(alignment: .leading, spacing: 12) {
      Button {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.35)) { expanded = open ? nil : recipe.id }
      } label: {
        HStack(spacing: 14) {
          Image(systemName: recipe.symbol).font(.title3).foregroundStyle(Theme.copperLight).frame(width: 30)
          VStack(alignment: .leading, spacing: 2) {
            Text(recipe.title).font(.headline).foregroundStyle(Theme.ink)
            Text("Trigger: \(recipe.trigger)").font(.caption).foregroundStyle(Theme.muted)
          }
          Spacer()
          Image(systemName: "chevron.down").rotationEffect(.degrees(open ? 180 : 0)).foregroundStyle(Theme.muted)
        }
        .frame(minHeight: 44)
      }
      .buttonStyle(.plain)
      .accessibilityValue(open ? "Expanded" : "Collapsed")
      .accessibilityHint(open ? "Hides the recipe" : "Shows the recipe")
      if open {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
            HStack(alignment: .top, spacing: 10) {
              Text("\(index + 1)").font(Theme.number(.footnote)).foregroundStyle(Theme.copperLight)
              Text(step).font(.subheadline).foregroundStyle(Theme.ink)
            }
          }
          if let signal = recipe.signal {
            Button { tag.signal(signal) } label: {
              Label("Feel “\(signal.name)” now", systemImage: "hand.tap.fill")
            }
            .buttonStyle(CopperButtonStyle(prominent: false))
            .disabled(!tag.status.isConnected)
            .padding(.top, 4)
          }
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
      }
    }
    .stitchedCard(padding: 16)
  }

  private var signals: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("The sleeve's vocabulary").sectionLabel()
      Text("Tap one to feel it. Each pairs a vibration with a light on the tag.")
        .font(.caption).foregroundStyle(Theme.muted)
      LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
        ForEach(JacketSignal.library) { signal in
          Button { tag.signal(signal) } label: {
            VStack(alignment: .leading, spacing: 6) {
              HStack(spacing: 4) {
                ForEach(Array((signal.light?.colors ?? [.white]).prefix(4).enumerated()), id: \.offset) { _, rgb in
                  Circle().fill(rgb.color).frame(width: 8, height: 8)
                }
                Spacer()
                Image(systemName: "waveform.path").font(.caption).foregroundStyle(Theme.muted)
              }
              Text(signal.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
              Text(signal.summary).font(.caption2).foregroundStyle(Theme.muted)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
          }
          .buttonStyle(.plain)
          .disabled(!tag.status.isConnected)
          .opacity(tag.status.isConnected ? 1 : 0.45)
        }
      }
      if !tag.canBuzz {
        Text("Snap the tag into your cuff to feel vibrations — the light works either way.")
          .font(.caption).foregroundStyle(.orange)
      }
    }
  }

  private var sleeveToShortcuts: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("The other direction").sectionLabel()
      VStack(alignment: .leading, spacing: 8) {
        Text("Run your Shortcuts from the sleeve").font(.headline)
        Text("On the Gestures tab, set a gesture (or Cover chord) to **Run a Shortcut**, then enter its exact name. While Jacquard is on screen, the gesture opens Shortcuts. In the background, tap the notification to run it; unlocking may be required. Focus and notification settings can delay alerts.")
          .font(.subheadline).foregroundStyle(Theme.muted)
        Text("Before your ride: Segway Mobility").font(.headline).padding(.top, 8)
        Text("1. In Shortcuts, create **Start my ride**.\n2. Add **Open App → Segway Mobility** and run it once to check it.\n3. In Jacquard's Gestures tab, choose your profile and a gesture, such as **Brush in → Run a Shortcut**.\n4. Enter **Start my ride** and turn **Return to Jacquard when finished** off.")
          .font(.subheadline).foregroundStyle(Theme.muted)
        Text("This opens the Segway app; it doesn't unlock or control your scooter. Set it up and use it while stopped. Jacquard can't create an iOS shortcut for you or silently open another app from a locked phone.")
          .font(.caption).foregroundStyle(Theme.muted)
        Link("Review “I'm riding my Segway”", destination: URL(string: "https://www.icloud.com/shortcuts/053b1b68c1d94e319022ef902942970c")!)
        Text("You can use that shared shortcut instead: enter “I'm riding my Segway” as the exact name. It also starts a workout, asks for an audio destination and listening mode, and sets volume to about 85%. Review or remove those extra actions if you only want to open Segway.")
          .font(.caption).foregroundStyle(Theme.muted)
        Text("Webhooks can run remote automations with a connection and network access, but can't remove the iPhone's unlock requirement.")
          .font(.caption).foregroundStyle(Theme.muted)
        Text("Siri works too: “Find my jacket with Jacquard”, “Jacquard status”, “Open Jacquard camera”.")
          .font(.subheadline).foregroundStyle(Theme.muted)
      }
      .stitchedCard(padding: 16)
    }
  }
}

extension RGB {
  var color: Color {
    Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
  }
}
