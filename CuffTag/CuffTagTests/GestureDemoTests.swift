import Combine
import JacquardSDK
import XCTest
@testable import CuffTag

@MainActor
final class GestureDemoTests: XCTestCase {
  private var defaults: UserDefaults!
  private var suiteName: String!

  override func setUp() async throws {
    suiteName = "GestureDemoTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)!
  }

  override func tearDown() async throws {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
  }

  func testRetryClearsFeedbackAndProgressWithoutLeavingSchool() {
    var demo = GestureDemoState(step: .school)
    for gesture in JQGesture.jacketGestures {
      demo.receive(.init(gesture: gesture, date: .now, source: .screen))
    }
    XCTAssertEqual(demo.learned.count, 4)
    XCTAssertNotNil(demo.lastGesture)
    demo.retry()
    XCTAssertEqual(demo.step, .school)
    XCTAssertTrue(demo.learned.isEmpty)
    XCTAssertNil(demo.lastGesture)
    demo.receive(.init(gesture: .brushIn, date: .now))
    XCTAssertEqual(demo.learned, [JQGesture.brushIn.rawValue])
    XCTAssertEqual(demo.lastGesture?.source, .jacket)
  }

  func testStartOverAndRetryFromCompletion() {
    var demo = GestureDemoState(step: .school)
    demo.receive(.init(gesture: .doubleTap, date: .now))
    demo.next()
    XCTAssertEqual(demo.step, .finished)
    demo.retry()
    XCTAssertEqual(demo.step, .school)
    XCTAssertTrue(demo.learned.isEmpty)
    demo.receive(.init(gesture: .shortCover, date: .now))
    demo.startOver()
    XCTAssertEqual(demo.step, .welcome)
    XCTAssertTrue(demo.learned.isEmpty)
    XCTAssertNil(demo.lastGesture)
  }

  func testWelcomePreviewsDoNotPrecompleteSchoolOrReplayStaleGestures() {
    var demo = GestureDemoState()
    demo.receive(.init(gesture: .brushOut, date: .now, source: .screen))
    XCTAssertEqual(demo.lastGesture?.gesture, .brushOut)
    XCTAssertTrue(demo.learned.isEmpty)
    demo.next()
    XCTAssertNil(demo.lastGesture)
    demo.receive(.init(gesture: .shortCover, date: .now))
    XCTAssertNil(demo.lastGesture)
    demo.next()
    XCTAssertEqual(demo.step, .school)
    XCTAssertTrue(demo.learned.isEmpty)
    demo.receive(.init(gesture: .noInference, date: .now))
    demo.receive(.init(gesture: .brushUp, date: .now))
    XCTAssertNil(demo.lastGesture)
    demo.receive(.init(gesture: .doubleTap, date: .now))
    let firstID = demo.lastGesture?.id
    demo.receive(.init(gesture: .doubleTap, date: .now))
    XCTAssertNotEqual(firstID, demo.lastGesture?.id)
    XCTAssertEqual(demo.learned.count, 1)
  }

  func testHardwareAndScreenEventsHaveDistinctSources() async {
    let manager = TestJacquardManager()
    let tag = TagController(manager: manager, defaults: defaults)
    let advertised = TestAdvertisedTag(identifier: UUID())
    let connected = TestConnectedTag(identifier: advertised.identifier)
    var demo = GestureDemoState(step: .school)
    let observation = tag.$lastGesture.compactMap { $0 }.sink { demo.receive($0) }
    defer { observation.cancel() }
    manager.state.send(.poweredOn)
    await drainMainQueue()
    tag.pair(.init(id: advertised.identifier, name: advertised.displayName,
                   tag: advertised, alreadyConnected: false))
    manager.connection.send(.connected(connected))
    await drainMainQueue()
    for gesture in JQGesture.jacketGestures {
      connected.notifications.send(gesture)
    }
    await drainMainQueue()
    XCTAssertEqual(demo.learned.count, 4)
    XCTAssertTrue(tag.recentGestures.allSatisfy { $0.source == .jacket })
    tag.simulate(.brushIn)
    XCTAssertEqual(tag.lastGesture?.source, .screen)
    XCTAssertEqual(demo.lastGesture?.source, .screen)
    demo.retry()
    XCTAssertNil(demo.lastGesture)
    XCTAssertNotNil(tag.lastGesture)
    XCTAssertEqual(tag.savedTagID, advertised.identifier)
  }

  func testDemoBlocksMappedActionsAndCameraOverrideButPreservesSettings() {
    let (performer, settings) = makePerformer()
    let profile = settings.activeProfileID
    let mapping = GestureAction(kind: .runShortcut, parameter: "My ride")
    settings.set(mapping, for: .brushIn, shifted: false, in: profile)
    var overrideCalls = 0
    performer.gestureOverride = { _ in
      overrideCalls += 1
      return true
    }
    performer.demoMode = true
    for gesture in JQGesture.jacketGestures { performer.handle(gesture) }
    XCTAssertNil(performer.lastPerformed)
    XCTAssertNil(performer.problem)
    XCTAssertFalse(performer.cameraRequested)
    XCTAssertFalse(performer.shiftArmed)
    XCTAssertFalse(performer.trainingMode)
    XCTAssertEqual(overrideCalls, 0)
    performer.demoMode = false
    XCTAssertEqual(settings.activeProfileID, profile)
    XCTAssertEqual(settings.action(for: .brushIn), mapping)
    performer.handle(.doubleTap)
    XCTAssertEqual(overrideCalls, 1)

    performer.gestureOverride = nil
    performer.trainingMode = true
    performer.demoMode = true
    performer.demoMode = false
    XCTAssertTrue(performer.trainingMode)
    performer.handle(.doubleTap)
    XCTAssertNil(performer.lastPerformed)
    performer.trainingMode = false
    settings.set(.init(kind: .none), for: .doubleTap, shifted: false, in: profile)
    performer.handle(.doubleTap)
    XCTAssertEqual(performer.lastPerformed?.gesture, .doubleTap)
  }

  func testOpeningDemoCancelsPendingCoverEvenAfterDemoCloses() async {
    let (performer, settings) = makePerformer()
    settings.set(.init(kind: .none), for: .shortCover, shifted: false, in: settings.activeProfileID)
    performer.handle(.shortCover)
    XCTAssertTrue(performer.shiftArmed)
    performer.demoMode = true
    XCTAssertFalse(performer.shiftArmed)
    performer.demoMode = false
    try? await Task.sleep(for: .seconds(GestureSettings.shiftWindow + 0.1))
    XCTAssertNil(performer.lastPerformed)
  }

  private func makePerformer() -> (ActionPerformer, GestureSettings) {
    let settings = GestureSettings(defaults: defaults)
    settings.hapticConfirmation = false
    let tag = TagController(manager: TestJacquardManager(), defaults: defaults)
    let media = MediaRouter(defaults: defaults)
    let volume = VolumeController()
    let performer = ActionPerformer(
      settings: settings, media: media, speech: SpeechAnnouncer(),
      volume: volume, tag: tag, finder: PhoneFinder(volume: volume))
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
