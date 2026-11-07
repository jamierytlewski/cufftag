import SwiftUI

struct GesturesView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @EnvironmentObject private var settings: GestureSettings
  @EnvironmentObject private var tag: TagController
  @EnvironmentObject private var performer: ActionPerformer
  @State private var editing: EditTarget?
  @State private var editingProfile: GestureProfile?
  @State private var showExperimental = false
  @State private var confirmReset = false

  struct EditTarget: Identifiable {
    let gesture: JQGesture
    let shifted: Bool
    var id: String { "\(gesture.rawValue)-\(shifted)" }
  }

  private var profileID: UUID { settings.activeProfileID }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          profilePicker
          layer(title: "On the cuff", subtitle: nil, gestures: JQGesture.jacketGestures, shifted: false)
          chords
          experimental
          feedback
          practice
          Button("Reset all profiles to defaults", role: .destructive) { confirmReset = true }
            .font(.footnote).frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, 20).padding(.bottom, 30)
      }
      .scrollIndicators(.hidden)
      .background(Theme.background)
      .navigationTitle("Gestures")
      .sheet(item: $editing) { target in
        ActionPickerSheet(
          gesture: target.gesture, shifted: target.shifted,
          action: settings.binding(for: target.gesture, shifted: target.shifted, in: profileID))
      }
      .sheet(item: $editingProfile) { profile in ProfileEditor(profile: profile) }
      .alert("Reset all profiles?", isPresented: $confirmReset) {
        Button("Cancel", role: .cancel) {}
        Button("Reset profiles", role: .destructive) { settings.resetToDefaults() }
      } message: {
        Text("This replaces your profiles and gesture assignments with the defaults.")
      }
    }
  }

  private var profilePicker: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Profile").sectionLabel()
      ScrollView(.horizontal) {
        HStack(spacing: 10) {
          ForEach(settings.profiles) { profile in
            let active = profile.id == profileID
            Button {
              withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) { settings.activeProfileID = profile.id }
            } label: {
              ProfileChip(profile: profile, selected: active)
            }
            .buttonStyle(TactileCardButtonStyle())
            .contextMenu {
              Button("Edit", systemImage: "pencil") { editingProfile = profile }
              if settings.profiles.count > 1 {
                Button("Delete", systemImage: "trash", role: .destructive) { settings.delete(profile) }
              }
            }
          }
          Button { editingProfile = settings.addProfile() } label: {
            Image(systemName: "plus")
              .frame(width: 44, height: 44)
              .background(Circle().fill(Color.white.opacity(0.07)))
              .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
          }
          .accessibilityLabel("Add profile")
          Button { editingProfile = settings.activeProfile } label: {
            Image(systemName: "pencil")
              .frame(width: 44, height: 44)
              .background(Circle().fill(Color.white.opacity(0.07)))
              .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
          }
          .accessibilityLabel("Edit active profile")
        }
        .padding(.vertical, 2)
      }
      .scrollIndicators(.hidden)
      Text("Switch from here, from a Shortcut, or with a gesture. Long-press a profile to edit.")
        .font(.caption).foregroundStyle(Theme.muted)
    }
  }

  private func layer(title: String, subtitle: String?, gestures: [JQGesture], shifted: Bool) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).sectionLabel()
      if let subtitle { Text(subtitle).font(.caption).foregroundStyle(Theme.muted) }
      VStack(spacing: 10) {
        ForEach(gestures) { gesture in
          let action = settings.action(for: gesture, shifted: shifted)
          Button { editing = EditTarget(gesture: gesture, shifted: shifted) } label: {
            GestureRow(
              gesture: gesture, action: action, shifted: shifted,
              note: !shifted && gesture == .shortCover && settings.coverIsShift
                ? "Or hold off ~1 s — Cover then another gesture is a chord" : nil)
          }
          .buttonStyle(TactileCardButtonStyle())
        }
      }
    }
  }

  @ViewBuilder
  private var chords: some View {
    VStack(alignment: .leading, spacing: 12) {
      Toggle(isOn: $settings.coverIsShift) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Cover chords").font(.headline)
          Text("Four gestures isn't many. Cover, then tap or brush within a second, for three more.")
            .font(.caption).foregroundStyle(Theme.muted)
        }
      }
      .tint(Theme.shift)
      .stitchedCard(padding: 16, tint: Theme.shift)
      if settings.coverIsShift {
        layer(title: "Cover, then…", subtitle: nil, gestures: GestureSettings.chordGestures, shifted: true)
      }
    }
  }

  private var experimental: some View {
    DisclosureGroup(isExpanded: $showExperimental) {
      VStack(alignment: .leading, spacing: 10) {
        Text("The SDK defines these for other Jacquard gear (bag straps). Your Levi's sleeve may never send them — if it does, they'll appear under Recently on the Jacket tab.")
          .font(.caption).foregroundStyle(Theme.muted)
        ForEach(JQGesture.experimentalGestures) { gesture in
          Button { editing = EditTarget(gesture: gesture, shifted: false) } label: {
            GestureRow(gesture: gesture, action: settings.action(for: gesture), shifted: false, note: nil)
          }
          .buttonStyle(TactileCardButtonStyle())
        }
      }
      .padding(.top, 8)
    } label: {
      Text("Experimental: brush up / down").sectionLabel()
    }
    .tint(Theme.muted)
  }

  private var feedback: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Feedback").sectionLabel()
      VStack(spacing: 14) {
        Toggle(isOn: $settings.hapticConfirmation) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Feel it on the sleeve")
            Text("Each action has its own signature — swell up to play, swell down to pause, two ticks to skip.")
              .font(.caption).foregroundStyle(Theme.muted)
          }
        }
        Divider().opacity(0.3)
        Toggle(isOn: $settings.spokenConfirmation) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Spoken confirmation")
            Text("Speaks confirmations for actions CuffTag can verify. Shortcut requests do not confirm external playback.").font(.caption).foregroundStyle(Theme.muted)
          }
        }
      }
      .tint(Theme.copper)
      .stitchedCard(padding: 16)
    }
  }

  private var practice: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Practice").sectionLabel()
      Toggle(isOn: $performer.trainingMode) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Practice mode")
          Text("Gestures only light up the sleeve and buzz — nothing plays. Watch the Jacket tab.")
            .font(.caption).foregroundStyle(Theme.muted)
        }
      }
      .tint(Theme.glow)
      .stitchedCard(padding: 16, tint: Theme.glow)
    }
  }
}

struct GestureRow: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  let gesture: JQGesture
  let action: GestureAction
  let shifted: Bool
  let note: String?

  private var accent: Color { shifted ? Theme.shift : Theme.glow }

  var body: some View {
    (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 14))) {
      ZStack {
        Circle().fill(accent.opacity(0.14))
        Circle().stroke(accent.opacity(0.28), lineWidth: 1)
        Image(systemName: gesture.symbol)
          .font(.callout.weight(.semibold))
          .foregroundStyle(accent)
      }
      .frame(width: 44, height: 44)
      VStack(alignment: .leading, spacing: 3) {
        Text((shifted ? "Cover + " : "") + gesture.friendlyName).font(.headline).foregroundStyle(Theme.ink)
        Text(note ?? gesture.hint).font(.caption).foregroundStyle(Theme.muted)
      }
      if !typeSize.isAccessibilitySize { Spacer() }
      HStack(spacing: 8) {
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
          Image(systemName: action.kind.systemImage).foregroundStyle(Theme.copperLight)
          Text(action.kind == .runShortcut && !action.parameter.isEmpty ? action.parameter : action.kind.title)
            .font(.caption.weight(.semibold)).foregroundStyle(Theme.ink)
            .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
        }
        if !typeSize.isAccessibilitySize {
          Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.muted.opacity(0.7))
        }
      }
      .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 142, alignment: typeSize.isAccessibilitySize ? .leading : .trailing)
    }
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 18)
        .fill(
          LinearGradient(
            colors: [Color.white.opacity(0.075), Color.white.opacity(0.04)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
    )
    .overlay(
      RoundedRectangle(cornerRadius: 18)
        .stroke(
          LinearGradient(
            colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
            startPoint: .top,
            endPoint: .bottom
          ),
          lineWidth: 1
        )
    )
  }
}

struct ActionPickerSheet: View {
  let gesture: JQGesture
  let shifted: Bool
  @Binding var action: GestureAction
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var tag: TagController
  @State private var notificationProblem: String?

  var body: some View {
    NavigationStack {
      List {
        ForEach(ActionCategory.allCases) { category in
          Section(category.rawValue) {
            ForEach(ActionKind.allCases.filter { $0.category == category }) { kind in
              Button {
                action.kind = kind
                if let signature = kind.signature { tag.signal(signature) }
              } label: {
                HStack {
                  Image(systemName: kind.systemImage).frame(width: 28).foregroundStyle(Theme.copperLight)
                  Text(kind.title).foregroundStyle(Theme.ink)
                  Spacer()
                  if action.kind == kind { Image(systemName: "checkmark").foregroundStyle(Theme.copper) }
                }
              }
              .accessibilityAddTraits(action.kind == kind ? .isSelected : [])
              if action.kind == kind, let prompt = kind.parameterPrompt {
                TextField(prompt, text: $action.parameter)
                  .textInputAutocapitalization(.never).autocorrectionDisabled()
                  .keyboardType(kind == .webhook ? .URL : .default)
                Text(kind == .runShortcut ? Self.shortcutNote : Self.webhookNote)
                  .font(.caption).foregroundStyle(Theme.muted)
                if kind == .runShortcut {
                  Toggle("Return to CuffTag when finished", isOn: $action.returnToCuffTag)
                  Text("Leave this off for shortcuts that open another app, such as Segway Mobility.")
                    .font(.caption).foregroundStyle(Theme.muted)
                  Button("Use the Segway example") {
                    action.parameter = "I'm riding my Segway"
                    action.returnToCuffTag = false
                  }
                  Text("Add “I'm riding my Segway” using the shared link below and review its workout and audio actions before using it. This button only fills in the name; it doesn't install or run the shortcut.")
                    .font(.caption).foregroundStyle(Theme.muted)
                  Link("Review shared Segway shortcut", destination: URL(string: "https://www.icloud.com/shortcuts/053b1b68c1d94e319022ef902942970c")!)
                  Link("Open Shortcuts", destination: URL(string: "shortcuts://")!)
                  if let notificationProblem {
                    Text(notificationProblem).font(.caption).foregroundStyle(.orange)
                    Link("Open notification settings", destination: URL(string: UIApplication.openNotificationSettingsURLString)!)
                  }
                }
              }
            }
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(Theme.background)
      .navigationTitle((shifted ? "Cover + " : "") + gesture.friendlyName)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
    .presentationDetents([.large])
    .task(id: action.kind) {
      guard action.kind == .runShortcut else { return }
      do {
        notificationProblem = try await NotificationPermission.request()
          ? nil : "Notifications are off. Background swipes cannot offer a shortcut until you enable notifications."
      } catch {
        notificationProblem = "Couldn't request notifications: \(error.localizedDescription)"
      }
    }
  }

  static let shortcutNote = "Enter the shortcut's exact name. It runs while CuffTag is on screen; in the background, a swipe requests a notification you tap to run it. You may need to unlock your phone. Focus and notification settings can delay alerts."
  static let webhookNote = "Sends a POST with {\"source\":\"cufftag\"} when the jacket is connected and a network is available. Useful for remote automations; it cannot bypass iOS restrictions to open an app on a locked iPhone."
}

struct ProfileEditor: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  @State var profile: GestureProfile
  @EnvironmentObject private var settings: GestureSettings
  @Environment(\.dismiss) private var dismiss

  private let symbols: [(symbol: String, name: String)] = [
    ("figure.walk", "Walking"), ("bicycle", "Cycling"), ("car.fill", "Driving"),
    ("moon.stars.fill", "Night"), ("briefcase.fill", "Work"), ("house.fill", "Home"),
    ("figure.run", "Running"), ("headphones", "Listening"), ("airplane", "Travel"),
    ("sparkles", "Sparkles"), ("leaf.fill", "Nature"), ("music.note", "Music"),
  ]

  var body: some View {
    NavigationStack {
      Form {
        Section {
          HStack {
            Spacer()
            ProfileChip(profile: profile, selected: true)
            Spacer()
          }
          .listRowBackground(Color.clear)
        }
        TextField("Name", text: $profile.name)
        Section("Icon") {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 64 : 48), spacing: 12)], spacing: 14) {
            ForEach(symbols, id: \.symbol) { item in
              Button { profile.symbol = item.symbol } label: {
                Image(systemName: item.symbol)
                  .font(.title3)
                  .frame(minWidth: 48, minHeight: 48)
                  .foregroundStyle(profile.symbol == item.symbol ? Color.black.opacity(0.85) : Theme.ink)
                  .background(
                    Circle().fill(
                      profile.symbol == item.symbol
                        ? AnyShapeStyle(LinearGradient(colors: [Theme.copperLight, Theme.copper], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(Color.white.opacity(0.06))
                    )
                  )
                  .overlay(Circle().stroke(Color.white.opacity(profile.symbol == item.symbol ? 0.3 : 0.08), lineWidth: 1))
                  .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .accessibilityLabel(item.name)
              .accessibilityAddTraits(profile.symbol == item.symbol ? .isSelected : [])
            }
          }
          .padding(.vertical, 6)
        }
      }
      .scrollContentBackground(.hidden)
      .background(Theme.background)
      .navigationTitle("Profile")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            settings.update(profile)
            settings.activeProfileID = profile.id
            dismiss()
          }
        }
      }
    }
    .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
  }
}
