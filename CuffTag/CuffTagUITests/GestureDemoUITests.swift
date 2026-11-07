import XCTest

@MainActor
final class GestureDemoUITests: XCTestCase {
  private let app = XCUIApplication()
  private var sleeve: XCUIElement { app.otherElements["demo-sleeve"] }

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  override func tearDownWithError() throws {
    app.terminate()
  }

  func testOpeningImageRecognizesAllFourGesturesAndResets() {
    launch(onboarded: false)
    XCTAssertTrue(sleeve.waitForExistence(timeout: 5))
    sleeve.swipeLeft()
    assertFeedback("Preview: Brush in")
    sleeve.swipeRight()
    assertFeedback("Preview: Brush out")
    sleeve.doubleTap()
    assertFeedback("Preview: Double tap")
    sleeve.press(forDuration: 0.6)
    assertFeedback("Preview: Cover")
    capture("Opening demo - Cover")
    app.buttons["Start over"].tap()
    XCTAssertFalse(app.staticTexts["demo-feedback"].exists)
    sleeve.doubleTap()
    assertFeedback("Preview: Double tap")
    app.buttons["Begin"].tap()
    reveal(app.buttons["Try without a tag"])
    app.buttons["Try without a tag"].tap()
    XCTAssertTrue(app.staticTexts["Gesture school"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["demo-progress"].label, "0 of 4 practiced")
  }

  func testSchoolRetryCompletionAndReentry() {
    launch()
    openSchool()
    sleeve.swipeLeft()
    sleeve.swipeRight()
    sleeve.doubleTap()
    sleeve.press(forDuration: 0.6)
    XCTAssertEqual(app.staticTexts["demo-progress"].label, "4 of 4 practiced")
    reveal(app.buttons["Try again"])
    app.buttons["Try again"].tap()
    XCTAssertEqual(app.staticTexts["demo-progress"].label, "0 of 4 practiced")
    XCTAssertFalse(app.staticTexts["demo-feedback"].exists)
    app.buttons["Preview Cover"].tap()
    XCTAssertEqual(app.staticTexts["demo-progress"].label, "1 of 4 practiced")
    reveal(app.buttons["Continue"])
    app.buttons["Continue"].tap()
    reveal(app.buttons["Try gestures again"])
    app.buttons["Try gestures again"].tap()
    XCTAssertEqual(app.staticTexts["demo-progress"].label, "0 of 4 practiced")
    capture("Gesture school - retry")
    app.buttons["Skip"].tap()
    openSchool()
    XCTAssertEqual(app.staticTexts["demo-progress"].label, "0 of 4 practiced")
    app.buttons["Skip"].tap()
    app.swipeDown()
    let jacketSleeve = app.otherElements["jacket-sleeve"]
    reveal(jacketSleeve, upwards: false)
    jacketSleeve.swipeLeft()
    XCTAssertEqual(app.staticTexts["sleeve-preview-feedback"].label, "Preview: Brush in")
  }

  func testSettingsReplayKeepsPracticeMode() {
    launch()
    app.tabBars.buttons["Gestures"].tap()
    let practice = app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Practice mode'")).firstMatch
    reveal(practice)
    if practice.value as? String != "1" { practice.tap() }
    app.tabBars.buttons["Jacket"].tap()
    app.buttons["Settings"].tap()
    reveal(app.buttons["Replay introduction"])
    app.buttons["Replay introduction"].tap()
    XCTAssertTrue(app.buttons["Begin"].waitForExistence(timeout: 5))
    sleeve.doubleTap()
    assertFeedback("Preview: Double tap")
    app.buttons["Skip"].tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    app.buttons["Done"].tap()
    app.tabBars.buttons["Gestures"].tap()
    reveal(practice)
    XCTAssertEqual(practice.value as? String, "1")
    practice.tap()
  }

  func testLargestTextCanScrollAcrossSleeveAndRetry() {
    launch(largeText: true)
    openSchool()
    XCTAssertTrue(app.buttons["Start over"].isHittable)
    XCTAssertTrue(app.buttons["Skip"].isHittable)
    reveal(sleeve)
    let before = sleeve.frame.minY
    sleeve.swipeUp()
    XCTAssertLessThan(sleeve.frame.minY, before, "Vertical drags must still scroll.")
    XCTAssertFalse(app.staticTexts["demo-feedback"].exists)
    reveal(app.buttons["Preview Cover"])
    app.buttons["Preview Cover"].tap()
    reveal(app.buttons["Try again"])
    capture("Gesture school - largest text")
    app.buttons["Try again"].tap()
    XCTAssertEqual(app.staticTexts["demo-progress"].label, "0 of 4 practiced")
    app.buttons["Start over"].tap()
    reveal(app.buttons["Begin"])
    XCTAssertTrue(app.buttons["Begin"].isHittable)
  }

  private func launch(onboarded: Bool = true, largeText: Bool = false) {
    app.launchArguments = [
      "-onboarded", onboarded ? "YES" : "NO",
      "-UIPreferredContentSizeCategoryName",
      largeText ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL",
    ]
    app.launch()
  }

  private func openSchool() {
    reveal(app.buttons["Gesture school"])
    app.buttons["Gesture school"].tap()
    XCTAssertTrue(app.staticTexts["Gesture school"].waitForExistence(timeout: 5))
  }

  private func reveal(_ element: XCUIElement, upwards: Bool = true) {
    for _ in 0..<14 {
      if element.exists && element.isHittable { return }
      if upwards { app.swipeUp() } else { app.swipeDown() }
    }
    XCTAssertTrue(element.isHittable, "Could not reach \(element)")
  }

  private func assertFeedback(_ text: String) {
    let feedback = app.staticTexts["demo-feedback"]
    XCTAssertTrue(feedback.waitForExistence(timeout: 3))
    XCTAssertEqual(feedback.label, text)
  }

  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
