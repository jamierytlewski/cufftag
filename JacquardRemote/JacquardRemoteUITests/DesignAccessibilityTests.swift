import XCTest

@MainActor
final class DesignAccessibilityTests: XCTestCase {
  private let app = XCUIApplication()

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  override func tearDownWithError() throws {
    app.terminate()
  }

  func testNativeNavigationAndProfileControls() {
    launch()
    capture("Jacket - default text")
    let settings = app.buttons["Settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    settings.tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    app.buttons["Done"].tap()

    app.tabBars.buttons["Gestures"].tap()
    capture("Gestures - default text")
    let edit = app.buttons["Edit active profile"]
    if !edit.isHittable { app.scrollViews.element(boundBy: 1).swipeLeft() }
    XCTAssertTrue(edit.isHittable)
    assertTouchTarget(edit)
    edit.tap()
    let cycling = app.buttons["Cycling"]
    XCTAssertTrue(cycling.waitForExistence(timeout: 5))
    assertTouchTarget(cycling)
    cycling.tap()
    XCTAssertTrue(cycling.isSelected)
    capture("Profile icon picker")
    app.buttons["Save"].tap()

    app.tabBars.buttons["Podcasts"].tap()
    capture("Podcasts - empty state")
    app.navigationBars.buttons["Add a show"].tap()
    XCTAssertTrue(app.textFields["RSS feed URL"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Add by RSS URL"].isEnabled)
    app.buttons["Done"].tap()
  }

  func testOnboardingRemainsReachableAtLargestTextSize() {
    launch(onboarded: false, largeText: true)
    let begin = app.buttons["Begin"]
    reveal(begin)
    assertTouchTarget(begin)
    capture("Onboarding - largest text")
    begin.tap()
    XCTAssertTrue(app.staticTexts["Find your tag"].waitForExistence(timeout: 5))
    capture("Pairing - largest text")
    XCTAssertTrue(app.buttons["Skip"].isHittable)
    app.buttons["Skip"].tap()
    XCTAssertTrue(app.tabBars.buttons["Jacket"].waitForExistence(timeout: 5))
  }

  func testLargestTextLayoutsAndResetConfirmation() {
    launch(largeText: true)
    capture("Jacket - largest text")
    app.tabBars.buttons["Gestures"].tap()
    let doubleTap = app.buttons.containing(.staticText, identifier: "Double tap").firstMatch
    reveal(doubleTap)
    capture("Gesture mapping - largest text")
    doubleTap.tap()
    XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
    app.buttons["Done"].tap()

    let reset = app.buttons["Reset all profiles to defaults"]
    reveal(reset)
    reset.tap()
    XCTAssertTrue(app.buttons["Reset profiles"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Cancel"].exists)
    app.buttons["Cancel"].tap()

    app.tabBars.buttons["Alerts"].tap()
    capture("Alerts - largest text")
    let recipe = app.buttons.containing(.staticText, identifier: "Someone special texts you").firstMatch
    reveal(recipe)
    recipe.tap()
    let steps = app.staticTexts["Choose the sender (and optionally words it contains)"]
    reveal(steps)
    XCTAssertTrue(steps.isHittable)
    capture("Alert recipe - largest text")
  }

  func testCameraControlsHaveAccessibleNames() {
    launch()
    let camera = app.buttons.containing(.staticText, identifier: "Sleeve Camera").firstMatch
    reveal(camera)
    camera.tap()
    let close = app.buttons["Close camera"]
    XCTAssertTrue(close.waitForExistence(timeout: 10))
    allowPendingSystemPermissions()
    for label in ["Close camera", "Photo timer", "Open Photos", "Take photo", "Flip camera"] {
      let button = app.buttons[label]
      XCTAssertTrue(button.exists, label)
      assertTouchTarget(button)
    }
    capture("Camera controls")
    close.tap()
  }

  private func launch(onboarded: Bool = true, largeText: Bool = false) {
    app.launchArguments = [
      "-onboarded", onboarded ? "YES" : "NO",
      "-UIPreferredContentSizeCategoryName",
      largeText ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL",
    ]
    app.launch()
  }

  private func reveal(_ element: XCUIElement) {
    for _ in 0..<18 {
      if element.exists && element.isHittable { return }
      app.swipeUp()
    }
    XCTAssertTrue(element.isHittable, "Could not reach \(element)")
  }

  private func assertTouchTarget(_ element: XCUIElement) {
    let settled = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in element.frame.width >= 44 && element.frame.height >= 44 },
      object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 3), .completed, element.label)
    XCTAssertGreaterThanOrEqual(element.frame.width, 44, element.label)
    XCTAssertGreaterThanOrEqual(element.frame.height, 44, element.label)
  }

  private func allowPendingSystemPermissions() {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    for _ in 0..<4 {
      let alert = springboard.alerts.firstMatch
      guard alert.waitForExistence(timeout: 1) else { return }
      let allowLabels = ["Allow", "Allow Once", "Allow While Using App"]
      guard let allow = allowLabels
        .map({ alert.buttons[$0] })
        .first(where: { $0.exists && $0.isHittable })
      else { return }
      allow.tap()
    }
  }

  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
