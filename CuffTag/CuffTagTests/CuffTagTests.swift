import AVFoundation
import Combine
import CoreBluetooth
import JacquardSDK
import XCTest
@testable import CuffTag

@MainActor
final class CuffTagTests: XCTestCase {
  private var defaults: UserDefaults!
  private var suiteName: String!

  override func setUp() async throws {
    suiteName = "CuffTagTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)!
  }

  override func tearDown() async throws {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
  }

  func testScanWaitsForBluetoothPermissionAndPower() async {
    let manager = TestJacquardManager()
    let controller = TagController(manager: manager, defaults: defaults)
    controller.startScanning()
    await drainMainQueue()
    XCTAssertEqual(manager.scanCount, 0)
    manager.state.send(.poweredOn)
    await drainMainQueue()
    XCTAssertEqual(manager.scanCount, 1)
    XCTAssertTrue(controller.isScanning)
  }

  func testLeavingPairingBeforeBluetoothIsReadyDoesNotStartScan() async {
    let manager = TestJacquardManager()
    let controller = TagController(manager: manager, defaults: defaults)
    controller.startScanning()
    controller.stopScanning()
    manager.state.send(.poweredOn)
    await drainMainQueue()
    XCTAssertEqual(manager.scanCount, 0)
  }

  func testScanResumesAfterBluetoothPowerCycle() async {
    let manager = TestJacquardManager()
    let controller = TagController(manager: manager, defaults: defaults)
    controller.startScanning()
    manager.state.send(.poweredOn)
    await drainMainQueue()
    manager.scanning.send(false)
    manager.state.send(.poweredOff)
    await drainMainQueue()
    XCTAssertFalse(controller.isScanning)
    XCTAssertEqual(controller.status, .bluetoothUnavailable("Bluetooth is off"))
    manager.state.send(.poweredOn)
    await drainMainQueue()
    XCTAssertEqual(manager.scanCount, 2)
  }

  func testScanErrorsAreVisibleAndRetryClearsThem() async {
    let manager = TestJacquardManager()
    manager.scanError = ManagerScanningError.bluetoothUnavailable(.poweredOff)
    let controller = TagController(manager: manager, defaults: defaults)
    controller.startScanning()
    manager.state.send(.poweredOn)
    await drainMainQueue()
    XCTAssertNotNil(controller.scanningProblem)
    manager.scanError = nil
    controller.startScanning()
    await drainMainQueue()
    XCTAssertNil(controller.scanningProblem)
    XCTAssertTrue(controller.isScanning)
  }

  func testPairingSavesIdentifierAndDeliversBufferedAndLiveGestures() async {
    let manager = TestJacquardManager()
    let controller = TagController(manager: manager, defaults: defaults)
    let advertised = TestAdvertisedTag(identifier: UUID())
    let connected = TestConnectedTag(identifier: advertised.identifier)
    connected.bufferedGesture = .doubleTap
    var received: [JQGesture] = []
    controller.onGesture = { received.append($0) }
    manager.state.send(.poweredOn)
    await drainMainQueue()
    controller.startScanning()
    controller.pair(.init(id: advertised.identifier, name: advertised.displayName,
                          tag: advertised, alreadyConnected: false))
    manager.connection.send(.connected(connected))
    await drainMainQueue()
    XCTAssertEqual(controller.status, .connected)
    XCTAssertEqual(defaults.string(forKey: "savedTagID"), advertised.identifier.uuidString)
    XCTAssertTrue(connected.subscribedBeforeReturning)
    XCTAssertEqual(received, [.doubleTap])
    XCTAssertFalse(controller.isScanning)
    connected.notifications.send(JQGesture.brushIn)
    connected.notifications.send(JQGesture.brushOut)
    connected.notifications.send(JQGesture.shortCover)
    connected.notifications.send(JQGesture.noInference)
    await drainMainQueue()
    XCTAssertEqual(received, [.doubleTap, .brushIn, .brushOut, .shortCover])
    XCTAssertEqual(controller.recentGestures.count, 4)
  }

  func testSavedTagReconnectsWithoutDuplicateConnectionRequests() async {
    let identifier = UUID()
    defaults.set(identifier.uuidString, forKey: "savedTagID")
    let manager = TestJacquardManager()
    let controller = TagController(manager: manager, defaults: defaults)
    manager.state.send(.poweredOn)
    await drainMainQueue()
    controller.reconnectSavedTag()
    controller.reconnectSavedTag()
    XCTAssertEqual(manager.connectionIDs, [identifier])
    controller.forgetTag()
    await drainMainQueue()
    XCTAssertNil(defaults.string(forKey: "savedTagID"))
    XCTAssertEqual(controller.status, .notPaired)
  }

  func testDisconnectWaitsForDisconnectedStateBeforeCancelling() async {
    defaults.set(UUID().uuidString, forKey: "savedTagID")
    let manager = TestJacquardManager()
    let states = PassthroughSubject<TagConnectionState, Error>()
    var cancelled = false
    manager.disconnectPublisher = states.handleEvents(receiveCancel: { cancelled = true }).eraseToAnyPublisher()
    let controller = TagController(manager: manager, defaults: defaults)

    controller.forgetTag()
    states.send(.preparingToConnect)
    await drainMainQueue()
    XCTAssertFalse(cancelled)

    states.send(.disconnected(nil))
    await drainMainQueue()
    XCTAssertTrue(cancelled)
  }

  func testEmptyBatteryResponseCompletesExactlyOnce() async {
    let manager = TestJacquardManager()
    let controller = TagController(manager: manager, defaults: defaults)
    let advertised = TestAdvertisedTag(identifier: UUID())
    let connected = TestConnectedTag(identifier: advertised.identifier)
    manager.state.send(.poweredOn)
    await drainMainQueue()
    controller.pair(.init(id: advertised.identifier, name: advertised.displayName,
                          tag: advertised, alreadyConnected: false))
    manager.connection.send(.connected(connected))
    await drainMainQueue()

    var responses: [Int?] = []
    controller.refreshBattery { responses.append($0) }
    await drainMainQueue()
    XCTAssertEqual(responses.count, 1)
    XCTAssertNil(responses.first ?? nil)
  }

  func testProfileKeepsShortcutNameAndReturnPreference() throws {
    let settings = GestureSettings(defaults: defaults)
    let action = GestureAction(kind: .runShortcut, parameter: "Start my ride", returnToCuffTag: false)
    settings.set(action, for: .brushIn, shifted: false, in: settings.activeProfileID)
    let reloaded = GestureSettings(defaults: defaults)
    XCTAssertEqual(reloaded.action(for: .brushIn), action)
    XCTAssertEqual(reloaded.action(for: .doubleTap).kind, .playPause)
    XCTAssertEqual(reloaded.action(for: .brushUp).kind, .none)
  }

  func testActivatingMissingProfileDoesNotChangeTheActiveProfile() {
    let settings = GestureSettings(defaults: defaults)
    let initialID = settings.activeProfileID
    XCTAssertNil(settings.activate(id: UUID()))
    XCTAssertEqual(settings.activeProfileID, initialID)
    let other = settings.profiles[1]
    XCTAssertEqual(settings.activate(id: other.id), other)
    XCTAssertEqual(settings.activeProfileID, other.id)
    XCTAssertEqual(GestureSettings(defaults: defaults).activeProfileID, other.id)
  }

  func testLegacyShortcutMappingsPreserveReturnBehavior() throws {
    let data = Data(#"{"kind":"runShortcut","parameter":"Existing shortcut"}"#.utf8)
    let action = try JSONDecoder().decode(GestureAction.self, from: data)
    XCTAssertTrue(action.returnToCuffTag)
    XCTAssertFalse(GestureAction(kind: .runShortcut).returnToCuffTag)
  }

  func testAppIntentEnumsKeepStableValuesAndCompleteDisplayRepresentations() {
    XCTAssertEqual(SignalOption.allCases.map(\.rawValue), [
      "nudge", "alert", "hello", "confirm", "bookmark", "error",
    ])
    XCTAssertEqual(Set(SignalOption.caseDisplayRepresentations.keys), Set(SignalOption.allCases))
    XCTAssertTrue(SignalOption.allCases.allSatisfy { JacketSignal.named($0.rawValue) != nil })

    XCTAssertEqual(LightColor.allCases.map(\.rawValue), [
      "copper", "indigo", "cyan", "white", "green", "amber", "red", "violet", "pink",
    ])
    XCTAssertEqual(Set(LightColor.caseDisplayRepresentations.keys), Set(LightColor.allCases))

    XCTAssertEqual(PodcastCommand.allCases.map(\.rawValue), [
      "playPause", "play", "pause", "skipForward", "skipBack", "nextEpisode", "bookmark",
    ])
    XCTAssertEqual(Set(PodcastCommand.caseDisplayRepresentations.keys), Set(PodcastCommand.allCases))
  }

  func testAppIntentsDeclareTheirExecutionModes() {
    XCTAssertEqual(SignalJacketIntent.supportedModes, .background)
    XCTAssertEqual(BuzzSleeveIntent.supportedModes, .background)
    XCTAssertEqual(FlashLightIntent.supportedModes, .background)
    XCTAssertEqual(FindJacketIntent.supportedModes, .background)
    XCTAssertEqual(GetJacketStatusIntent.supportedModes, .background)
    XCTAssertEqual(GetJacketBatteryIntent.supportedModes, .background)
    XCTAssertEqual(SetProfileIntent.supportedModes, .background)
    XCTAssertEqual(OpenSleeveCameraIntent.supportedModes, .foreground(.immediate))
    XCTAssertEqual(PodcastControlIntent.supportedModes, .background)
    XCTAssertEqual(PlayLatestEpisodeIntent.supportedModes, .background)
  }

  func testOpenAppShortcutURLDoesNotBringUserBackToJacquard() throws {
    let url = try XCTUnwrap(ActionPerformer.shortcutURL("  Start my ride \n"))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
    XCTAssertEqual(components.scheme, "shortcuts")
    XCTAssertEqual(components.host, "run-shortcut")
    XCTAssertEqual(components.queryItems, [URLQueryItem(name: "name", value: "Start my ride")])
  }

  func testShortcutURLHandlesReservedCharactersAndOptionalReturn() throws {
    let name = "Ride & relax + coffee / #1?"
    let url = try XCTUnwrap(ActionPerformer.shortcutURL(name, returnToCuffTag: true))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
    XCTAssertEqual(components.host, "x-callback-url")
    XCTAssertEqual(components.path, "/run-shortcut")
    XCTAssertEqual(components.queryItems?.first?.value, name)
    XCTAssertEqual(components.queryItems?.first { $0.name == "x-success" }?.value, "cufftag://done")
    XCTAssertNil(ActionPerformer.shortcutURL(" \n "))
  }

  func testCoverChordUsesAlternateMappingAndCancelsBaseAction() async {
    let (performer, settings) = makePerformer()
    settings.set(.init(kind: .none), for: .shortCover, shifted: false, in: settings.activeProfileID)
    settings.set(.init(kind: .none), for: .brushIn, shifted: true, in: settings.activeProfileID)
    performer.handle(.shortCover)
    XCTAssertTrue(performer.shiftArmed)
    performer.handle(.brushIn)
    XCTAssertFalse(performer.shiftArmed)
    XCTAssertEqual(performer.lastPerformed?.gesture, .brushIn)
    XCTAssertEqual(performer.lastPerformed?.shifted, true)
    try? await Task.sleep(for: .seconds(GestureSettings.shiftWindow + 0.1))
    XCTAssertEqual(performer.lastPerformed?.gesture, .brushIn)
  }

  func testEnteringPracticeOrCameraCancelsPendingCoverAction() async {
    let (performer, _) = makePerformer()
    performer.handle(.shortCover)
    performer.trainingMode = true
    XCTAssertFalse(performer.shiftArmed)
    try? await Task.sleep(for: .seconds(GestureSettings.shiftWindow + 0.1))
    XCTAssertNil(performer.lastPerformed)
    performer.trainingMode = false
    performer.handle(.shortCover)
    performer.gestureOverride = { _ in true }
    XCTAssertFalse(performer.shiftArmed)
    performer.handle(.doubleTap)
    XCTAssertNil(performer.lastPerformed)
  }

  func testCoverAloneRunsBaseMappingAfterChordWindow() async {
    let (performer, settings) = makePerformer()
    settings.set(.init(kind: .none), for: .shortCover, shifted: false, in: settings.activeProfileID)
    performer.handle(.shortCover)
    XCTAssertNil(performer.lastPerformed)
    try? await Task.sleep(for: .seconds(GestureSettings.shiftWindow + 0.1))
    XCTAssertFalse(performer.shiftArmed)
    XCTAssertEqual(performer.lastPerformed?.gesture, .shortCover)
    XCTAssertEqual(performer.lastPerformed?.shifted, false)
  }

  func testCameraCannotStartCountdownBeforeItIsReady() async {
    let tag = TagController(manager: TestJacquardManager(), defaults: defaults)
    let camera = SleeveCamera(tag: tag)
    camera.timer = .three
    camera.shutter()
    await drainMainQueue()
    XCTAssertNil(camera.countdown)
    XCTAssertFalse(camera.isCapturing)
  }

  func testCameraCoverGestureStartsThreeSecondCountdownEvenWhenTimerIsOff() async {
    let tag = TagController(manager: TestJacquardManager(), defaults: defaults)
    let camera = SleeveCamera(tag: tag)
    camera.enableDemoPreview(thumbnail: nil)
    camera.timer = .off
    XCTAssertTrue(camera.handle(.shortCover))
    await drainMainQueue()
    XCTAssertEqual(camera.countdown, 3)
    camera.stop()
  }

  func testApplePodcastsSourceRequiresShortcutsWithoutControllingOtherPlayers() throws {
    let store = PodcastStore()
    let player = PodcastPlayer(store: store)
    let media = MediaRouter(player: player, defaults: defaults)
    media.activeSource = .podcasts
    XCTAssertNil(media.externalSkipForwardShortcut)
    XCTAssertNil(media.externalSkipBackShortcut)
    XCTAssertNil(media.externalPlayPauseShortcut)

    media.activeSource = .applePodcasts
    media.applePodcastsSkipForwardShortcut = "Podcast Skip 30"
    media.applePodcastsSkipBackShortcut = "Podcast Back 15"
    media.applePodcastsPlayPauseShortcut = "  Podcast Play Pause \n"
    XCTAssertEqual(media.externalPlayPauseShortcut, "Podcast Play Pause")
    XCTAssertEqual(media.externalSkipForwardShortcut, "Podcast Skip 30")
    XCTAssertEqual(media.externalSkipBackShortcut, "Podcast Back 15")
    XCTAssertThrowsError(try media.playPause())
    XCTAssertThrowsError(try media.next())
    XCTAssertThrowsError(try media.previous())
    media.applePodcastsPlayPauseShortcut = " \n "
    XCTAssertNil(media.externalPlayPauseShortcut)
    media.activeSource = .podcasts
  }

  func testMediaSourceKeepsOnePodcastLibraryAndPreservesShortcutSettings() {
    defaults.set(MediaSource.podcasts.rawValue, forKey: "activeSource")
    defaults.set("My Play Pause", forKey: "applePodcastsPlayPauseShortcut")
    let player = PodcastPlayer(store: PodcastStore(), restorePlayback: false)
    let media = MediaRouter(player: player, defaults: defaults)
    XCTAssertEqual(media.activeSource, .applePodcasts)
    XCTAssertEqual(media.externalPlayPauseShortcut, "My Play Pause")
    XCTAssertFalse(MediaSource.selectableSources.contains(.podcasts))
    XCTAssertNil(player.episode)
    media.activeSource = .appleMusic
    XCTAssertEqual(MediaRouter(player: player, defaults: defaults).activeSource, .appleMusic)
  }

  func testFailedVideoCaptureReportsFailureInsteadOfSaving() async throws {
    let tag = TagController(manager: TestJacquardManager(), defaults: defaults)
    let camera = SleeveCamera(tag: tag)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
    try Data([0, 1, 2]).write(to: url)
    camera.fileOutput(
      AVCaptureMovieFileOutput(), didFinishRecordingTo: url, from: [],
      error: NSError(domain: AVFoundationErrorDomain, code: -1,
                     userInfo: [NSLocalizedDescriptionKey: "Test recording failure"]))
    await drainMainQueue()
    XCTAssertEqual(camera.problem, "Recording failed: Test recording failure")
    XCTAssertFalse(camera.hasPendingSave)
    XCTAssertFalse(camera.isRecording)
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
  }

  private func makePerformer() -> (ActionPerformer, GestureSettings) {
    let settings = GestureSettings(defaults: defaults)
    settings.hapticConfirmation = false
    let tag = TagController(manager: TestJacquardManager(), defaults: defaults)
    let store = PodcastStore()
    let player = PodcastPlayer(store: store)
    let media = MediaRouter(player: player, defaults: defaults)
    let volume = VolumeController()
    let performer = ActionPerformer(
      settings: settings, media: media, speech: SpeechAnnouncer(player: player),
      volume: volume, tag: tag, podcasts: store, finder: PhoneFinder(volume: volume, player: player))
    return (performer, settings)
  }

  private func drainMainQueue() async {
    for _ in 0..<4 {
      await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
      }
    }
  }
}
