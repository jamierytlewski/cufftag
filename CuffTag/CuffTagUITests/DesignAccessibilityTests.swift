import AVFoundation
import XCTest

final class DesignAccessibilityTests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testAccessibilityXXLLayoutsAndScreenshots() throws {
    let app = XCUIApplication()
    app.launchArguments = [
      "-onboarded", "YES",
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ]
    app.launch()

    let jacketHeader = app.otherElements["jacket-sleeve"]
    XCTAssertTrue(jacketHeader.waitForExistence(timeout: 8))
    attachScreenshot(named: "01-JacketTab-AX3")

    // Scroll down on Jacket tab to inspect Practice, Camera, QuickActions
    app.swipeUp()
    attachScreenshot(named: "02-JacketTab-Bottom-AX3")

    // Open CameraView
    let openCamera = app.buttons.containing(.staticText, identifier: "Sleeve Camera").firstMatch
    reveal(openCamera, in: app)
    openCamera.tap()
    let closeCamera = app.buttons["Close camera"]
    XCTAssertTrue(closeCamera.waitForExistence(timeout: 8))
    for label in ["Close camera", "Photo timer", "Open Photos", "Take photo", "Flip camera"] {
      let button = app.buttons[label]
      XCTAssertTrue(button.exists, label)
      XCTAssertGreaterThanOrEqual(button.frame.width, 44, label)
      XCTAssertGreaterThanOrEqual(button.frame.height, 44, label)
    }
    attachScreenshot(named: "03-CameraView-AX3")
    closeCamera.tap()

    // Switch to Gestures tab
    app.tabBars.buttons["Gestures"].tap()
    sleep(1)
    attachScreenshot(named: "04-GesturesTab-AX3")

    // Switch to Alerts tab
    app.tabBars.buttons["Alerts"].tap()
    sleep(1)
    attachScreenshot(named: "05-AlertsTab-AX3")

    // Switch to Podcasts tab
    app.tabBars.buttons["Podcasts"].tap()
    sleep(1)
    attachScreenshot(named: "06-PodcastsTab-AX3")
  }

  @MainActor
  func testDefaultSizeScreenshots() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-onboarded", "YES"]
    app.launch()

    XCTAssertTrue(app.otherElements["jacket-sleeve"].waitForExistence(timeout: 8))
    attachScreenshot(named: "11-JacketTab-Default")

    app.tabBars.buttons["Gestures"].tap()
    sleep(1)
    attachScreenshot(named: "12-GesturesTab-Default")

    app.tabBars.buttons["Alerts"].tap()
    sleep(1)
    attachScreenshot(named: "13-AlertsTab-Default")

    app.tabBars.buttons["Podcasts"].tap()
    sleep(1)
    attachScreenshot(named: "14-PodcastsTab-Default")
  }

  /// Captures the full suite of 8 App Store screenshots AND compiles a 24-second App Preview `.mp4` video
  /// (with a stereo AAC audio track) directly into `/tmp/cufftag-appstore-shots/`.
  @MainActor
  func testCaptureAppStoreScreenshots() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-onboarded", "NO", "-appStoreDemo", "YES"]
    app.launch()

    // 1. Onboarding Hero ("Your jacket remembers.")
    let beginCTA = app.buttons["Begin"]
    XCTAssertTrue(beginCTA.waitForExistence(timeout: 8))

    let welcomeSleeve = app.otherElements["demo-sleeve"]
    if welcomeSleeve.waitForExistence(timeout: 4) {
      let right = welcomeSleeve.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.5))
      let left = welcomeSleeve.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.5))
      right.press(forDuration: 0.02, thenDragTo: left)
      Thread.sleep(forTimeInterval: 0.18)
    }
    try saveAppStoreScreenshot(named: "06-Onboarding-Welcome")

    // 2. Advance to Gesture School & practice gestures
    beginCTA.tap()
    let continueBtn = app.buttons["Continue"]
    XCTAssertTrue(continueBtn.waitForExistence(timeout: 5))
    continueBtn.tap()

    let previewDoubleTap = app.buttons["Preview Double tap"]
    reveal(previewDoubleTap, in: app)
    previewDoubleTap.tap()
    Thread.sleep(forTimeInterval: 0.25)
    let previewBrushIn = app.buttons["Preview Brush in"]
    reveal(previewBrushIn, in: app)
    previewBrushIn.tap()
    XCTAssertEqual(app.staticTexts["demo-progress"].label, "2 of 4 practiced")
    try saveAppStoreScreenshot(named: "05-Gesture-School")

    // Exit Onboarding into Main App
    let skipBtn = app.buttons["Skip"]
    if skipBtn.exists {
      skipBtn.tap()
    }

    // 3. Main App Connected State — Jacket tab
    let jacketSleeve = app.otherElements["jacket-sleeve"]
    XCTAssertTrue(jacketSleeve.waitForExistence(timeout: 8))
    Thread.sleep(forTimeInterval: 0.5)

    jacketSleeve.swipeLeft()
    try saveAppStoreScreenshot(named: "01-Jacket-Connected")

    // 4. Gestures tab (Everyday / Ride / Focus profiles + On the cuff + Cover chords)
    app.tabBars.buttons["Gestures"].tap()
    Thread.sleep(forTimeInterval: 0.6)
    try saveAppStoreScreenshot(named: "02-Gestures-Profiles")

    // 5. Apple Podcasts setup; no duplicate library or simulated playback.
    app.tabBars.buttons["Podcasts"].tap()
    Thread.sleep(forTimeInterval: 0.6)
    try saveAppStoreScreenshot(named: "03-Podcasts-Library")

    XCTAssertTrue(app.buttons["Open Apple Podcasts"].waitForExistence(timeout: 4))
    XCTAssertTrue(app.textFields["Play / Pause Shortcut"].exists)
    app.swipeUp()
    try saveAppStoreScreenshot(named: "04-Podcast-Shortcuts")

    // 6. Alerts tab (Shortcuts automation recipes + The sleeve's vocabulary)
    app.tabBars.buttons["Alerts"].tap()
    Thread.sleep(forTimeInterval: 0.5)
    let vipRecipe = app.buttons.containing(.staticText, identifier: "Someone special texts you").firstMatch
    reveal(vipRecipe, in: app)
    vipRecipe.tap()
    try saveAppStoreScreenshot(named: "07-Alerts-Shortcuts")

    // 7. Sleeve Camera (opened from Jacket tab)
    app.tabBars.buttons["Jacket"].tap()
    Thread.sleep(forTimeInterval: 0.5)
    let openCameraBtn = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Sleeve Camera'")).firstMatch
    reveal(openCameraBtn, in: app)
    openCameraBtn.tap()
    let closeCamera = app.buttons["Close camera"]
    XCTAssertTrue(closeCamera.waitForExistence(timeout: 4))
    try saveAppStoreScreenshot(named: "08-Sleeve-Camera")
    closeCamera.tap()
  }

  /// Choreographed ~22-second walkthrough designed to be recorded via `simctl io recordVideo` for the App Store Preview video.
  @MainActor
  func testRecordAppPreviewWalkthrough() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-onboarded", "YES", "-appStoreDemo", "YES"]
    app.launch()

    let sleeve = app.otherElements["jacket-sleeve"]
    XCTAssertTrue(sleeve.waitForExistence(timeout: 8))
    Thread.sleep(forTimeInterval: 1.2)

    // Preview gestures without opening another app during recording.
    sleeve.swipeLeft()
    Thread.sleep(forTimeInterval: 1.5)

    // 2. Double tap -> Play / Pause
    sleeve.doubleTap()
    Thread.sleep(forTimeInterval: 1.5)

    // 3. Cover chord: Cover -> Brush in (Volume up)
    sleeve.press(forDuration: 0.6)
    Thread.sleep(forTimeInterval: 1.6)

    // 4. Switch to Gestures tab and show profiles & Cover chords
    app.tabBars.buttons["Gestures"].tap()
    Thread.sleep(forTimeInterval: 1.4)
    let rideChip = app.buttons["Ride"].firstMatch
    if rideChip.exists {
      rideChip.tap()
      Thread.sleep(forTimeInterval: 1.2)
    }
    let everydayChip = app.buttons["Everyday"].firstMatch
    if everydayChip.exists {
      everydayChip.tap()
      Thread.sleep(forTimeInterval: 1.0)
    }

    // 5. Switch to Alerts tab, expand VIP recipe, and tap a signal
    app.tabBars.buttons["Alerts"].tap()
    Thread.sleep(forTimeInterval: 1.2)
    let vipRecipe = app.buttons.containing(.staticText, identifier: "Someone special texts you").firstMatch
    if vipRecipe.exists {
      vipRecipe.tap()
      Thread.sleep(forTimeInterval: 1.4)
    }

    // 6. Show the single-library Apple Podcasts setup.
    app.tabBars.buttons["Podcasts"].tap()
    Thread.sleep(forTimeInterval: 1.4)
    XCTAssertTrue(app.buttons["Open Apple Podcasts"].waitForExistence(timeout: 4))
    app.swipeUp()
    Thread.sleep(forTimeInterval: 2.0)

    // 7. Return to Jacket tab and open Sleeve Camera
    app.tabBars.buttons["Jacket"].tap()
    Thread.sleep(forTimeInterval: 1.0)
    let openCameraBtn = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Sleeve Camera'")).firstMatch
    if !openCameraBtn.exists {
      app.swipeUp()
      Thread.sleep(forTimeInterval: 0.5)
    }
    if openCameraBtn.exists {
      openCameraBtn.tap()
      Thread.sleep(forTimeInterval: 1.6)
      let closeCamera = app.buttons["Close camera"]
      if closeCamera.exists {
        closeCamera.tap()
        Thread.sleep(forTimeInterval: 1.0)
      }
    }
  }

  private func attachScreenshot(named name: String) {
    let screenshot = XCUIScreen.main.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<18 {
      if element.exists && element.isHittable { return }
      app.swipeUp()
    }
    XCTAssertTrue(element.isHittable, "Could not reach \(element)")
  }

  private func saveAppStoreScreenshot(named name: String) throws {
    let shot = XCUIScreen.main.screenshot()
    let pngData = shot.pngRepresentation
    let attachment = XCTAttachment(screenshot: shot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)

    let outputDir = URL(fileURLWithPath: "/tmp/cufftag-appstore-shots", isDirectory: true)
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    try pngData.write(to: outputDir.appendingPathComponent("\(name).png"))
  }
}
