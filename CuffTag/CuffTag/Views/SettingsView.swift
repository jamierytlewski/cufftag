import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var tag: TagController
  @EnvironmentObject private var media: MediaRouter
  @Environment(\.dismiss) private var dismiss
  @AppStorage("onboarded") private var onboarded = false
  @State private var newName = ""
  @State private var confirmForget = false
  @State private var showPairing = false
  @State private var showIntroduction = false

  var body: some View {
    NavigationStack {
      Form {
        Section("Your jacket") {
          LabeledContent("Status", value: tag.status.label)
          LabeledContent("Tag", value: tag.tagName ?? "—")
          LabeledContent("Gear", value: tag.gearName ?? "Not snapped in")
          LabeledContent("Tag firmware", value: tag.firmwareVersion ?? "Connect to read")
          LabeledContent("Battery", value: tag.batteryLevel.map { "\($0)%\(tag.isCharging ? " · charging" : "")" } ?? "—")
          HStack {
            TextField("Rename tag", text: $newName)
            Button("Save") {
              tag.rename(newName.trimmingCharacters(in: .whitespaces))
              newName = ""
            }
            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || !tag.status.isConnected)
          }
        }

        Section {
          Picker("Media gestures control", selection: $media.activeSource) {
            ForEach(MediaSource.allCases) { source in
              Label(source.title, systemImage: source.systemImage).tag(source)
            }
          }
        } footer: {
          Text("Switches automatically to whatever you last played. Apple Podcasts and Spotify can't be controlled by other apps on iOS — that's why CuffTag has its own podcast player.")
        }

        Section {
          Button("Pair a different tag") { showPairing = true }
          Button("Forget this tag", role: .destructive) { confirmForget = true }
        } footer: {
          Text("Pairing trouble? Hold the tag button 4 seconds until it pulses. If it still won't show, forget the tag in iOS Settings › Bluetooth and try again.")
        }

        Section {
          Button("Replay introduction") { showIntroduction = true }
        } footer: {
          Text("Revisit the opening demo and Gesture school without changing your pairing, profiles or shortcuts.")
        }

        Section("About") {
          if let expiry = ProvisioningInfo.expirationDate {
            LabeledContent("This build expires", value: expiry.formatted(date: .abbreviated, time: .shortened))
          }
          LabeledContent("Firmware updates", value: "Not available")
          Text("This app uses the firmware already on your tag. The mandatory cloud-update check is bypassed; no firmware is installed or replaced. Some older firmware may still be incompatible.")
            .font(.caption).foregroundStyle(Theme.muted)
          Link("Jacquard SDK on GitHub", destination: URL(string: "https://github.com/google/JacquardSDKiOS")!)
        }
      }
      .scrollContentBackground(.hidden)
      .background(Theme.background)
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
      .confirmationDialog("Forget this tag?", isPresented: $confirmForget) {
        Button("Forget", role: .destructive) {
          tag.forgetTag()
          dismiss()
          onboarded = false
        }
      }
      .sheet(isPresented: $showPairing) { PairingSheet() }
      .fullScreenCover(isPresented: $showIntroduction) {
        OnboardingView { showIntroduction = false }
      }
    }
  }
}

struct PairingSheet: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var tag: TagController

  var body: some View {
    NavigationStack {
      ScrollView {
        PairingPanel { dismiss() }
          .padding(20)
      }
        .background(Theme.background)
        .navigationTitle("Pair your tag")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
  }
}

/// Scanning list shared by onboarding and the pairing sheet.
struct PairingPanel: View {
  var onConnected: () -> Void
  @EnvironmentObject private var tag: TagController
  @State private var pairingID: UUID?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      TagIllustration()
        .frame(height: 150).frame(maxWidth: .infinity)
      Text("Take the tag out of your cuff and **hold its button for 4 seconds** until the light starts pulsing white.")
        .font(.callout).foregroundStyle(Theme.ink)

      HStack {
        Text(tag.isScanning ? "Looking for tags…" : "Nearby tags").sectionLabel()
        Spacer()
        if tag.isScanning {
          ProgressView().controlSize(.small)
        } else {
          Button("Scan again") { tag.startScanning() }
            .font(.caption.weight(.semibold))
            .frame(minHeight: 44)
        }
      }

      if case .bluetoothUnavailable(let reason) = tag.status {
        Label(reason, systemImage: "exclamationmark.triangle.fill")
          .font(.caption).foregroundStyle(.orange)
      }
      if let problem = tag.scanningProblem {
        Label(problem, systemImage: "exclamationmark.triangle.fill")
          .font(.caption).foregroundStyle(.orange)
      }

      VStack(spacing: 10) {
        if tag.discoveredTags.isEmpty {
          Text("Nothing yet. Tags stop advertising after a minute — hold the button again if needed.")
            .font(.caption).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .stitchedCard(padding: 14)
        }
        ForEach(tag.discoveredTags) { item in
          Button {
            pairingID = item.id
            tag.pair(item)
          } label: {
            HStack {
              Rivet(size: 14)
              VStack(alignment: .leading) {
                Text(item.name).font(.headline).foregroundStyle(Theme.ink)
                Text(item.alreadyConnected ? "Already known to this iPhone" : "Ready to pair")
                  .font(.caption).foregroundStyle(Theme.muted)
              }
              Spacer()
              if pairingID == item.id, case .connecting(let step) = tag.status {
                Text(step).font(.caption).foregroundStyle(Theme.glow)
              } else {
                Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
              }
            }
            .stitchedCard(padding: 14)
          }
          .buttonStyle(.plain)
        }
      }

      if case .disconnected(let reason) = tag.status, pairingID != nil {
        Label(reason, systemImage: "exclamationmark.triangle.fill")
          .font(.caption).foregroundStyle(.orange)
      }
    }
    .onAppear { tag.startScanning() }
    .onDisappear { tag.stopScanning() }
    .onChange(of: tag.status) { _, status in
      if status.isConnected, pairingID != nil { onConnected() }
    }
  }
}

/// A drawn Jacquard snap tag with a pulsing LED.
struct TagIllustration: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  var color: Color = .white
  @State private var pulse = false
  private var animating: Bool { !reduceMotion && scenePhase == .active }

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 22)
        .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
        .frame(width: 92, height: 130)
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.15)))
        .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
      VStack(spacing: 18) {
        Circle()
          .fill(color)
          .frame(width: 10, height: 10)
          .shadow(color: color, radius: pulse ? 14 : 2)
          .opacity(pulse ? 1 : 0.35)
        Circle().stroke(Color.white.opacity(0.25), lineWidth: 2).frame(width: 34, height: 34)
      }
    }
    .animation(animating ? .easeInOut(duration: 1.0).repeatForever() : nil, value: pulse)
    .onChange(of: animating, initial: true) { _, value in pulse = value }
    .accessibilityHidden(true)
  }
}
