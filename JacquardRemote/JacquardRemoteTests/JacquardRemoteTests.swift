import AVFoundation
import Combine
import CoreBluetooth
import JacquardSDK
import XCTest
@testable import JacquardRemote

@MainActor
final class JacquardRemoteTests: XCTestCase {
  private var defaults: UserDefaults!
  private var suiteName: String!

  override func setUp() async throws {
    suiteName = "JacquardRemoteTests.\(UUID().uuidString)"
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

  func testProfileKeepsShortcutNameAndReturnPreference() throws {
    let settings = GestureSettings(defaults: defaults)
    let action = GestureAction(kind: .runShortcut, parameter: "Start my ride", returnToJacquard: false)
    settings.set(action, for: .brushIn, shifted: false, in: settings.activeProfileID)
    let reloaded = GestureSettings(defaults: defaults)
    XCTAssertEqual(reloaded.action(for: .brushIn), action)
    XCTAssertEqual(reloaded.action(for: .doubleTap).kind, .playPause)
    XCTAssertEqual(reloaded.action(for: .brushUp).kind, .none)
  }

  func testLegacyShortcutMappingsPreserveReturnBehavior() throws {
    let data = Data(#"{"kind":"runShortcut","parameter":"Existing shortcut"}"#.utf8)
    let action = try JSONDecoder().decode(GestureAction.self, from: data)
    XCTAssertTrue(action.returnToJacquard)
    XCTAssertFalse(GestureAction(kind: .runShortcut).returnToJacquard)
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
    let url = try XCTUnwrap(ActionPerformer.shortcutURL(name, returnToJacquard: true))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
    XCTAssertEqual(components.host, "x-callback-url")
    XCTAssertEqual(components.path, "/run-shortcut")
    XCTAssertEqual(components.queryItems?.first?.value, name)
    XCTAssertEqual(components.queryItems?.first { $0.name == "x-success" }?.value, "jacquard://done")
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
    let media = MediaRouter(player: player)
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
