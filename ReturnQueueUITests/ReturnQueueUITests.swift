import CoreGraphics
import Foundation
import XCTest

@MainActor
final class ReturnQueueUITests: XCTestCase {
  func testCreateRelaunchCancelAndSaveEditUsesActualDisk() {
    let root = UUID().uuidString
    let app = launch(root: root)
    defer { app.terminate() }
    openAdd(app)
    attach(app, name: "01-Add-empty")
    enter(app, field: "title", text: "Test sneakers")
    enter(app, field: "merchant", text: "Example Store")
    expandOptional(app)
    enter(app, field: "dropOffLocation", text: "UPS Store Market St")
    enter(app, field: "returnBy", text: "2026-10-06")
    enter(app, field: "expectedRefund", text: "79.99")
    save(app)
    app.terminate()
    app.launch()
    openFirstItem(app)
    XCTAssertTrue(app.staticTexts["Test sneakers"].firstMatch.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["UPS Store Market St"].exists)
    XCTAssertTrue(
      app.descendants(matching: .any).matching(
        NSPredicate(format: "label CONTAINS %@", "Oct 6, 2026")
      ).firstMatch.exists)
    XCTAssertTrue(
      app.descendants(matching: .any).matching(
        NSPredicate(format: "label CONTAINS %@", "$79.99")
      ).firstMatch.exists)
    attach(app, name: "02-Detail-saved")
    app.buttons["detail.edit"].tap()
    enter(app, field: "title", text: "Cancelled title")
    app.buttons["editor.cancel"].tap()
    XCTAssertTrue(app.staticTexts["Test sneakers"].firstMatch.waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Cancelled title"].exists)
    app.buttons["detail.edit"].tap()
    enter(app, field: "title", text: "Edited sneakers")
    save(app)
    XCTAssertTrue(app.staticTexts["Edited sneakers"].firstMatch.waitForExistence(timeout: 5))
    app.terminate()
    app.launch()
    openFirstItem(app)
    XCTAssertTrue(app.staticTexts["Edited sneakers"].firstMatch.waitForExistence(timeout: 5))
  }

  func testInvalidInputRetainsDraftUntilCorrectedAndUnknownsStayUnknown() {
    let app = launch(root: UUID().uuidString)
    defer { app.terminate() }
    openAdd(app)
    enter(app, field: "title", text: "Invalid draft")
    enter(app, field: "merchant", text: "Store")
    expandOptional(app)
    enter(app, field: "returnBy", text: "2026-02-30")
    enter(app, field: "purchasePrice", text: "1.234")
    app.buttons["editor.save"].tap()
    expectSaveFailure(app)
    XCTAssertTrue(app.buttons["editor.cancel"].exists)
    XCTAssertEqual(locateInput(app, "returnBy").value as? String, "2026-02-30")
    enter(app, field: "returnBy", text: "")
    enter(app, field: "purchasePrice", text: "")
    save(app)
    XCTAssertEqual(itemRows(app).count, 1)
    openFirstItem(app)
    XCTAssertTrue(app.staticTexts["Not set"].firstMatch.waitForExistence(timeout: 5))
  }

  func testWriteFailurePreservesDraftAndPreviousSavedRecordAcrossRelaunch() {
    let root = UUID().uuidString
    let app = launch(root: root)
    defer { app.terminate() }
    createMinimal(app, title: "Original sneakers")
    app.terminate()
    app.launchArguments = arguments(root: root, extras: ["-rq-test-write-failure"])
    app.launch()
    openFirstItem(app)
    app.buttons["detail.edit"].tap()
    enter(app, field: "title", text: "Unsaved sneakers")
    app.buttons["editor.save"].tap()
    expectSaveFailure(app)
    XCTAssertEqual(locateInput(app, "title").value as? String, "Unsaved sneakers")
    XCTAssertTrue(app.buttons["editor.cancel"].isEnabled)
    app.buttons["editor.cancel"].tap()
    XCTAssertTrue(app.staticTexts["Original sneakers"].firstMatch.waitForExistence(timeout: 5))
    app.terminate()
    app.launchArguments = arguments(root: root)
    app.launch()
    openFirstItem(app)
    XCTAssertTrue(app.staticTexts["Original sneakers"].firstMatch.waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Unsaved sneakers"].exists)
  }

  func testCorruptLoadWarnsBeforeSharingAndExplicitRetryRecoversOriginal() {
    let root = UUID().uuidString
    let app = launch(root: root)
    defer { app.terminate() }
    createMinimal(app, title: "Recovery sneakers")
    app.terminate()
    app.launchArguments = arguments(
      root: root, extras: ["-rq-test-corrupt", "-rq-test-repair-on-retry"])
    app.launch()
    XCTAssertTrue(app.buttons["load.retry"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["load.export"].exists)
    XCTAssertFalse(app.buttons["queue.add"].exists && app.buttons["queue.add"].isEnabled)
    XCTAssertFalse(app.staticTexts["No returns yet"].exists)
    app.buttons["load.export"].tap()
    let alert = app.alerts.firstMatch
    XCTAssertTrue(alert.waitForExistence(timeout: 5))
    let warning = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
    XCTAssertTrue(warning.lowercased().contains("damaged"))
    XCTAssertTrue(warning.lowercased().contains("personal"))
    // SwiftUI exposes the same alert action as two nested accessibility buttons.
    let confirm = alert.buttons.matching(identifier: "recovery.confirm")
    XCTAssertGreaterThan(confirm.count, 0)
    XCTAssertTrue(
      confirm.allElementsBoundByIndex.allSatisfy { $0.label == "Export original data" })
    confirm.firstMatch.tap()
    // System sharing keeps the simulator's language rather than the app's launch locale.
    let close = app.buttons["header.closeButton"]
    let appeared = close.waitForExistence(timeout: 5)
    if !appeared { diagnose(app, name: "Missing-native-share") }
    XCTAssertTrue(appeared, "Native sharing sheet did not appear")
    let filename = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH %@", "ReturnQueue-original-")
    ).firstMatch
    XCTAssertTrue(filename.exists, "Native sharing did not receive the original archive copy")
    attach(app, name: "03-Recovery-native-share")
    close.tap()
    XCTAssertTrue(app.buttons["load.retry"].waitForExistence(timeout: 5))
    app.buttons["load.retry"].tap()
    XCTAssertTrue(itemRows(app).firstMatch.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["queue.add"].isEnabled)
    openFirstItem(app)
    XCTAssertTrue(app.staticTexts["Recovery sneakers"].firstMatch.waitForExistence(timeout: 5))
  }

  private func launch(root: String) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = arguments(root: root)
    let attachment = XCTAttachment(string: "Isolated DEBUG test root: \(root)")
    attachment.lifetime = .keepAlways
    add(attachment)
    app.launch()
    XCTAssertTrue(app.buttons["queue.add"].waitForExistence(timeout: 5))
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "enabled == true"), object: app.buttons["queue.add"])
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, "Saved data did not load")
    return app
  }

  private func arguments(root: String, extras: [String] = []) -> [String] {
    ["-rq-ui-testing", "-rq-test-root", root, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
      + extras
  }

  private func openAdd(_ app: XCUIApplication) {
    app.buttons["queue.add"].tap()
    XCTAssertTrue(app.buttons["editor.save"].waitForExistence(timeout: 5))
  }

  private func createMinimal(_ app: XCUIApplication, title: String) {
    openAdd(app)
    enter(app, field: "title", text: title)
    enter(app, field: "merchant", text: "Example Store")
    save(app)
  }

  private func itemRows(_ app: XCUIApplication) -> XCUIElementQuery {
    app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "queue.item."))
  }

  private func openFirstItem(_ app: XCUIApplication) {
    let item = itemRows(app).firstMatch
    XCTAssertTrue(item.waitForExistence(timeout: 5))
    item.tap()
    XCTAssertTrue(app.buttons["detail.edit"].waitForExistence(timeout: 5))
  }

  private func save(_ app: XCUIApplication) {
    let button = app.buttons["editor.save"]
    button.tap()
    let gone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: button)
    XCTAssertEqual(
      XCTWaiter.wait(for: [gone], timeout: 5), .completed, "Editor did not commit/dismiss")
  }

  private func expandOptional(_ app: XCUIApplication) {
    let disclosure = app.staticTexts["editor.optional"]
    XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
    for _ in 0..<8 {
      if visibleInEditor(app, disclosure) { break }
      scrollToward(app, disclosure)
    }
    XCTAssertTrue(visibleInEditor(app, disclosure))
    disclosure.tap()
  }

  private func textField(_ app: XCUIApplication, _ rawValue: String) -> XCUIElement {
    let id = "editor.\(rawValue)"
    let field = app.textFields[id]
    if field.exists { return field }
    return app.textViews[id]
  }

  private func enter(_ app: XCUIApplication, field: String, text: String) {
    let input = locateInput(app, field)
    input.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    let old = input.value as? String ?? ""
    let count = old == input.placeholderValue ? 0 : old.count
    if count > 0 {
      input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count))
    }
    if !text.isEmpty { input.typeText(text) }
  }

  private func locateInput(_ app: XCUIApplication, _ field: String) -> XCUIElement {
    if !textField(app, field).exists {
      for _ in 0..<12 {
        if reachableInput(app, "title") { break }
        scrollForm(app, up: false)
      }
    }
    for _ in 0..<16 {
      // Form cells can be created lazily, so reacquire the element type after every scroll.
      if reachableInput(app, field) { break }
      scrollToward(app, textField(app, field))
    }
    let input = textField(app, field)
    if !visibleInEditor(app, input) { diagnose(app, name: "Unreachable-field-\(field)") }
    XCTAssertTrue(input.exists, "Missing field \(field)")
    XCTAssertTrue(visibleInEditor(app, input), "Field \(field) is not reachable")
    return input
  }

  private func reachableInput(_ app: XCUIApplication, _ field: String) -> Bool {
    let input = textField(app, field)
    return visibleInEditor(app, input)
  }

  private func expectSaveFailure(_ app: XCUIApplication) {
    let error = app.descendants(matching: .any)["editor.error"]
    for _ in 0..<16 {
      if visibleInEditor(app, error) { break }
      scrollToward(app, error)
    }
    XCTAssertTrue(error.exists, "Save failure was not displayed")
  }

  private func visibleInEditor(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
    guard element.exists else { return false }
    let viewport = editorViewport(app)
    let frame = element.frame
    // SwiftUI can report hittable for cells covered by the sheet's navigation bar.
    return frame.minY >= viewport.minY && frame.maxY <= viewport.maxY && element.isHittable
  }

  private func scrollToward(_ app: XCUIApplication, _ element: XCUIElement) {
    let above = element.exists && element.frame.midY < editorViewport(app).minY
    scrollForm(app, up: !above)
  }

  private func editorViewport(_ app: XCUIApplication) -> CGRect {
    let form = app.collectionViews["editor.form"]
    XCTAssertTrue(form.exists, "Editor Form is missing")
    let frame = form.frame
    let keyboard = app.keyboards.firstMatch
    // XCTest's keyboard frame can exclude its suggestion strip and input accessory.
    let bottom = min(frame.maxY - 16, keyboard.exists ? keyboard.frame.minY - 80 : frame.maxY - 16)
    let navigation = app.navigationBars.matching(identifier: "Add return").firstMatch
    let editNavigation = app.navigationBars.matching(identifier: "Edit return").firstMatch
    let bar = navigation.exists ? navigation : editNavigation
    XCTAssertTrue(bar.exists, "Editor navigation bar is missing")
    let top = max(frame.minY, bar.frame.maxY) + 16
    XCTAssertGreaterThan(bottom - top, 60, "Form has no reachable scroll area")
    return CGRect(x: frame.minX, y: top, width: frame.width, height: bottom - top)
  }

  private func scrollForm(_ app: XCUIApplication, up: Bool) {
    let viewport = editorViewport(app)
    // Short drags keep the next field within the visible area rather than overshooting it.
    let distance = min(180, viewport.height * 0.5)
    let lower = viewport.midY + distance * 0.5
    let upper = viewport.midY - distance * 0.5
    let origin = app.coordinate(withNormalizedOffset: .zero)
    let a = origin.withOffset(CGVector(dx: viewport.midX, dy: up ? lower : upper))
    let b = origin.withOffset(CGVector(dx: viewport.midX, dy: up ? upper : lower))
    a.press(forDuration: 0.01, thenDragTo: b)
  }

  private func attach(_ app: XCUIApplication, name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func diagnose(_ app: XCUIApplication, name: String) {
    let hierarchy = XCTAttachment(string: app.debugDescription)
    hierarchy.name = "\(name)-hierarchy"
    hierarchy.lifetime = .keepAlways
    add(hierarchy)
    attach(app, name: name)
  }
}
