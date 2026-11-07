import Foundation
import JacquardSDK
import UIKit
import UserNotifications

struct PerformedAction: Equatable {
  let gesture: JQGesture?
  let action: GestureAction
  let shifted: Bool
  let date: Date
}

/// Executes the action mapped to each gesture, including Cover chords and sleeve signatures.
@MainActor
final class ActionPerformer: ObservableObject {
  @Published private(set) var lastPerformed: PerformedAction?
  /// True while Cover has armed the alternate layer and we're waiting for the next gesture.
  @Published private(set) var shiftArmed = false
  /// While practising gestures, nothing runs — the sleeve just confirms it felt you.
  @Published var trainingMode = false {
    didSet { if trainingMode { disarmShift() } }
  }
  /// Replay temporarily blocks actions without changing the user's Practice mode setting.
  @Published var demoMode = false {
    didSet { if demoMode { disarmShift() } }
  }
  /// Set when a gesture asks for the camera; the UI presents it.
  @Published var cameraRequested = false
  @Published var problem: String?
  /// While the camera is on screen it takes over the sleeve.
  var gestureOverride: ((JQGesture) -> Bool)? {
    didSet { disarmShift() }
  }

  private let settings: GestureSettings
  private let media: MediaRouter
  private let speech: SpeechAnnouncer
  private let volume: VolumeController
  private let tag: TagController
  private let finder: PhoneFinder
  private var shiftTimer: DispatchWorkItem?

  init(
    settings: GestureSettings, media: MediaRouter, speech: SpeechAnnouncer,
    volume: VolumeController, tag: TagController, finder: PhoneFinder
  ) {
    self.settings = settings
    self.media = media
    self.speech = speech
    self.volume = volume
    self.tag = tag
    self.finder = finder
  }

  func handle(_ gesture: JQGesture) {
    if demoMode {
      tag.signal(.confirm)
      return
    }
    if let gestureOverride, gestureOverride(gesture) {
      disarmShift()
      return
    }
    if trainingMode {
      tag.signal(.confirm)
      return
    }
    if shiftArmed {
      disarmShift()
      if gesture == .shortCover {
        // Cover twice: run Cover's own action.
        perform(settings.action(for: .shortCover), from: .shortCover)
      } else {
        perform(settings.action(for: gesture, shifted: true), from: gesture, shifted: true)
      }
      return
    }
    if gesture == .shortCover && settings.coverIsShift && hasShiftedActions {
      armShift()
      return
    }
    perform(settings.action(for: gesture), from: gesture)
  }

  private var hasShiftedActions: Bool {
    settings.activeProfile.shifted.values.contains { $0.kind != .none }
  }

  private func armShift() {
    shiftArmed = true
    if settings.hapticConfirmation { tag.signal(.shift) }
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.shiftArmed else { return }
      self.disarmShift()
      // No follow-up gesture: Cover on its own runs its normal action.
      self.perform(self.settings.action(for: .shortCover), from: .shortCover)
    }
    shiftTimer = work
    DispatchQueue.main.asyncAfter(deadline: .now() + GestureSettings.shiftWindow, execute: work)
  }

  private func disarmShift() {
    shiftTimer?.cancel()
    shiftTimer = nil
    shiftArmed = false
  }

  func perform(_ action: GestureAction, from gesture: JQGesture? = nil, shifted: Bool = false) {
    lastPerformed = PerformedAction(gesture: gesture, action: action, shifted: shifted, date: Date())
    var signature = action.kind.signature
    switch action.kind {
    case .none:
      break
    case .playPause, .next, .previous:
      if media.activeSource == .applePodcasts {
        let shortcutName: String?
        switch action.kind {
        case .playPause: shortcutName = media.externalPlayPauseShortcut
        case .next: shortcutName = media.externalSkipForwardShortcut
        default: shortcutName = media.externalSkipBackShortcut
        }
        guard let shortcutName else {
          reportShortcutProblem("Enter the exact name of your \(action.kind.title) Shortcut in Settings.")
          return
        }
        runShortcut(
          GestureAction(kind: .runShortcut, parameter: shortcutName, returnToCuffTag: true),
          signalOnSuccess: settings.hapticConfirmation && gesture != nil)
        return
      }
      do {
        switch action.kind {
        case .playPause:
          try media.playPause()
          signature = media.isPlaying ? .play : .pause
          confirm(media.isPlaying ? "Playing" : "Paused")
        case .next: try media.next()
        default: try media.previous()
        }
      } catch {
        reportShortcutProblem(error.localizedDescription)
        return
      }
    case .volumeUp:
      volume.change(by: 0.0625)
    case .volumeDown:
      volume.change(by: -0.0625)
    case .speakNowPlaying:
      speech.speak(media.nowPlayingDescription ?? "Nothing is playing.")
    case .speakTime:
      let time = Date().formatted(date: .omitted, time: .shortened)
      speech.speak("It's \(time).")
    case .speakBattery:
      tag.refreshBattery { [weak self] level in
        guard let self else { return }
        if let level {
          self.speech.speak("Jacket battery is at \(level) percent.")
        } else {
          self.speech.speak("I can't reach your jacket right now.")
        }
      }
    case .findPhone:
      finder.ring()
    case .openCamera:
      if UIApplication.shared.applicationState == .active {
        cameraRequested = true
      } else {
        postCameraNotification()
      }
    case .nextProfile:
      let profile = settings.cycleProfile()
      speech.speak("\(profile.name) profile.")
    case .webhook:
      callWebhook(action.parameter)
    case .runShortcut:
      signature = nil
      runShortcut(action, signalOnSuccess: settings.hapticConfirmation && gesture != nil)
    }
    if let signature, settings.hapticConfirmation, gesture != nil { tag.signal(signature) }
  }

  private func confirm(_ text: String) {
    if settings.spokenConfirmation { speech.speak(text) }
  }

  private func postCameraNotification() {
    cameraRequested = true
    Task {
      let center = UNUserNotificationCenter.current()
      let notificationSettings = await center.notificationSettings()
      if [.authorized, .provisional, .ephemeral].contains(notificationSettings.authorizationStatus) {
        let content = UNMutableNotificationContent()
        content.title = "Open Sleeve Camera"
        content.body = "Tap to open the camera — then Double tap or Cover your cuff to take a photo."
        content.interruptionLevel = .timeSensitive
        content.sound = .default
        content.userInfo = ["openCamera": true]
        let request = UNNotificationRequest(identifier: "sleeve-camera", content: content, trigger: nil)
        do {
          try await center.add(request)
        } catch {
          reportShortcutProblem("Couldn't show the camera notification: \(error.localizedDescription)")
        }
      } else {
        speech.speak("Tap CuffTag to open the camera.")
      }
    }
  }

  private func callWebhook(_ urlString: String) {
    guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)),
      url.scheme?.hasPrefix("http") == true
    else {
      speech.speak("The webhook address isn't set.")
      return
    }
    // Keep running briefly if we were woken in the background by a gesture.
    let taskID = UIApplication.shared.beginBackgroundTask(withName: "webhook")
    Task {
      var request = URLRequest(url: url, timeoutInterval: 10)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try? JSONSerialization.data(withJSONObject: [
        "source": "cufftag", "timestamp": ISO8601DateFormatter().string(from: Date()),
      ])
      let ok = (try? await URLSession.shared.data(for: request)).map {
        (($0.1 as? HTTPURLResponse)?.statusCode ?? 500) < 400
      } ?? false
      if !ok { self.speech.speak("The webhook failed.") }
      UIApplication.shared.endBackgroundTask(taskID)
    }
  }

  private func runShortcut(_ action: GestureAction, signalOnSuccess: Bool) {
    guard let url = Self.shortcutURL(
      action.parameter, returnToCuffTag: action.returnToCuffTag)
    else {
      reportShortcutProblem("Choose a shortcut by entering its exact name in Gestures.")
      return
    }
    problem = nil
    Task {
      if UIApplication.shared.applicationState == .active {
        await openShortcut(url, signalOnSuccess: signalOnSuccess)
        return
      }
      let center = UNUserNotificationCenter.current()
      let notificationSettings = await center.notificationSettings()
      guard [.authorized, .provisional, .ephemeral].contains(notificationSettings.authorizationStatus),
        notificationSettings.alertSetting == .enabled
      else {
        reportShortcutProblem(
          "Enable CuffTag notifications in Settings to run a Shortcut from the background, or open CuffTag first.")
        return
      }
      let content = UNMutableNotificationContent()
      content.title = "Run “\(action.parameter.trimmingCharacters(in: .whitespacesAndNewlines))”"
      content.body = "Tap to run your shortcut. Unlock your iPhone if asked."
      content.interruptionLevel = .active
      content.sound = .default
      content.userInfo = ["shortcutURL": url.absoluteString]
      let request = UNNotificationRequest(identifier: "shortcut", content: content, trigger: nil)
      do {
        try await center.add(request)
        if signalOnSuccess { tag.signal(.confirm) }
      } catch {
        reportShortcutProblem("Couldn't show the shortcut notification: \(error.localizedDescription)")
      }
    }
  }

  func openShortcut(_ url: URL, signalOnSuccess: Bool = false) async {
    if await UIApplication.shared.open(url) {
      if signalOnSuccess { tag.signal(.confirm) }
    } else {
      reportShortcutProblem("Couldn't open Shortcuts. Check that Apple's Shortcuts app is installed.")
    }
  }

  private func reportShortcutProblem(_ message: String) {
    problem = message
    speech.speak(message)
    if settings.hapticConfirmation { tag.signal(.error) }
  }

  static func shortcutURL(_ name: String, returnToCuffTag: Bool = false) -> URL? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    var components = URLComponents(
      string: returnToCuffTag ? "shortcuts://x-callback-url/run-shortcut" : "shortcuts://run-shortcut")
    components?.queryItems = [URLQueryItem(name: "name", value: trimmed)]
    if returnToCuffTag {
      components?.queryItems?.append(contentsOf: [
        URLQueryItem(name: "x-success", value: "cufftag://done"),
        URLQueryItem(name: "x-cancel", value: "cufftag://done"),
      ])
    }
    return components?.url
  }
}
