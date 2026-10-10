import CoreGraphics
import Foundation
import XCTest

@MainActor
final class ReturnQueueUITests: XCTestCase {
  func testQueueGroupsLocationsOrdersEnteredDatesAndMovesOnlyAfterSavedEdit() {
    let app = launch(root: UUID().uuidString)
    defer { app.terminate() }
    // Create the unknown-date record first: date ordering must beat creation ordering.
    let jacket = createTripItem(
      app, title: "Trip jacket", merchant: "Store B", location: "ups STORE market st")
    let sneakers = createTripItem(
      app, title: "Trip sneakers", merchant: "Store A", location: "UPS Store Market St",
      returnBy: "2020-01-01")
    let backpack = createTripItem(
      app, title: "Trip backpack", merchant: "Store A", location: "USPS Mission St",
      returnBy: "2026-10-05")
    let initialOrder = [sneakers, jacket, backpack]
    let initialGroups = [groupID(jacket), groupID(backpack)]
    assertTripQueue(
      app, rows: initialOrder, groups: initialGroups, members: [[sneakers, jacket], [backpack]])
    XCTAssertTrue(app.buttons[sneakers].label.contains("Store A"))
    XCTAssertTrue(app.buttons[jacket].label.contains("Store B"))
    XCTAssertTrue(app.buttons[jacket].label.contains("Return by: Not set"))
    XCTAssertFalse(app.buttons[jacket].label.contains("$0.00"))
    XCTAssertTrue(app.buttons[sneakers].label.contains("Past your entered date"))
    attach(app, name: "04-Queue-grouped")

    app.buttons[jacket].tap()
    XCTAssertTrue(app.buttons["detail.edit"].waitForExistence(timeout: 5))
    app.buttons["detail.edit"].tap()
    expandOptional(app)
    enter(app, field: "dropOffLocation", text: "USPS Mission St")
    app.buttons["editor.cancel"].tap()
    backToQueue(app)
    assertTripQueue(
      app, rows: initialOrder, groups: initialGroups, members: [[sneakers, jacket], [backpack]])

    app.buttons[jacket].tap()
    XCTAssertTrue(app.buttons["detail.edit"].waitForExistence(timeout: 5))
    app.buttons["detail.edit"].tap()
    expandOptional(app)
    enter(app, field: "dropOffLocation", text: "USPS Mission St")
    enter(app, field: "returnBy", text: "2021-01-01")
    save(app)
    backToQueue(app)
    let savedOrder = [sneakers, jacket, backpack]
    // Moving the earliest-created item also changes the destination group's representative.
    let savedGroups = [groupID(sneakers), groupID(jacket)]
    assertTripQueue(
      app, rows: savedOrder, groups: savedGroups, members: [[sneakers], [jacket, backpack]])
    XCTAssertEqual(itemRows(app).matching(identifier: jacket).count, 1)
    app.terminate()
    app.launch()
    assertTripQueue(
      app, rows: savedOrder, groups: savedGroups, members: [[sneakers], [jacket, backpack]])
    app.buttons[jacket].tap()
    XCTAssertTrue(app.buttons["detail.edit"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["USPS Mission St"].exists)
    XCTAssertTrue(
      app.descendants(matching: .any).matching(
        NSPredicate(format: "label CONTAINS %@", "Jan 1, 2021")
      ).firstMatch.exists)
  }

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
    guard cancelNativeRecoveryShare(app) else { return }
    let retry = app.buttons["load.retry"]
    // Retry is already present behind the sheet; its existence alone does not mean it can act.
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == true AND hittable == true AND enabled == true"),
      object: retry)
    let readiness = XCTWaiter.wait(for: [ready], timeout: 5)
    if readiness != .completed { diagnose(app, name: "Recovery-retry-readiness") }
    XCTAssertEqual(readiness, .completed, "Retry remained blocked after native sharing dismissed")
    retry.tap()
    XCTAssertTrue(itemRows(app).firstMatch.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["queue.add"].isEnabled)
    openFirstItem(app)
    XCTAssertTrue(app.staticTexts["Recovery sneakers"].firstMatch.waitForExistence(timeout: 5))
  }

  func testManualMoneyAndCreditPartialClosureRoutesToHistoryAndSurvivesRelaunch() {
    let root = UUID().uuidString
    let app = launch(root: root)
    defer { app.terminate() }
    openAdd(app)
    enter(app, field: "title", text: "Manual partial sneakers")
    enter(app, field: "merchant", text: "Example Store")
    expandOptional(app)
    enter(app, field: "expectedRefund", text: "100")
    enter(app, field: "purchasePrice", text: "150")
    save(app)
    let recordID = itemRows(app).element(boundBy: 0).identifier
      .replacingOccurrences(of: "queue.item.", with: "")
    openFirstItem(app)
    us3Tap(app, id: "detail.dropOff")
    us3CaptureFreshForm(app, form: "state.form", name: "US3-drop-off-form-before-input")
    us3Enter(app, form: "state.form", id: "state.droppedOffDate", text: "2026-10-03")
    us3Enter(app, form: "state.form", id: "state.expectedRefundDate", text: "2026-10-20")
    us3Tap(app, id: "state.save", form: "state.form")
    us3Confirm(app)
    us3AssertTab(app, id: "tab.waiting")
    us3AssertValue(app, id: "refund.droppedOffDate", contains: "2026")
    us3CaptureListAndReopen(
      app, title: "Waiting for refund", prefix: "waiting", recordID: recordID,
      name: "US3-waiting-list-after-drop-off")
    us3AddEvent(
      app, amount: "50", kind: "Money", date: "2026-10-04", note: "First manual payment",
      screenshotName: "US3-reimbursement-form-before-input")
    us3AddEvent(
      app, amount: "30", kind: "Store credit", date: "2026-10-05", note: "Recorded credit")
    us3AssertValue(app, id: "refund.money", contains: "$50.00")
    us3AssertValue(app, id: "refund.credit", contains: "$30.00")
    us3AssertValue(app, id: "refund.expected", contains: "$100.00")
    us3AssertValue(app, id: "refund.difference", contains: "$20.00")
    us3AssertTab(app, id: "tab.waiting")
    attach(app, name: "US3-manual-separate-totals")
    us3Tap(app, id: "detail.close")
    us3CaptureFreshForm(app, form: "state.form", name: "US3-closure-form-before-input")
    us3Choose(app, id: "state.outcome", label: "Partial refund", form: "state.form")
    us3Enter(app, form: "state.form", id: "state.closureNote", text: "Accepted $20 return fee")
    us3Tap(app, id: "state.save", form: "state.form")
    XCTAssertTrue(app.buttons["refund.confirm"].waitForExistence(timeout: 5))
    us3AssertTab(app, id: "tab.waiting")
    us3Confirm(app)
    us3AssertTab(app, id: "tab.history")
    us3AssertValue(app, id: "refund.outcome", contains: "Partial refund")
    us3AssertValue(app, id: "refund.closureNote", contains: "Accepted $20 return fee")
    attach(app, name: "US3-partial-closure-history-detail")
    us3CaptureListAndReopen(
      app, title: "History", prefix: "history", recordID: recordID,
      name: "US3-history-list-after-partial-closure")
    app.terminate()
    app.launch()
    us3OpenTabItem(
      app, tab: "tab.history", prefix: "history.item.", title: "Manual partial sneakers")
    us3AssertValue(app, id: "refund.money", contains: "$50.00")
    us3AssertValue(app, id: "refund.credit", contains: "$30.00")
    us3AssertValue(app, id: "refund.expected", contains: "$100.00")
    us3AssertValue(app, id: "refund.difference", contains: "$20.00")
    us3AssertValue(app, id: "refund.outcome", contains: "Partial refund")
    us3AssertValue(app, id: "refund.closureNote", contains: "Accepted $20 return fee")
    us3AssertValue(app, id: "refund.droppedOffDate", contains: "2026")
    let edits = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "reimbursement.edit."))
    XCTAssertEqual(edits.count, 2)
  }

  func testReimbursementEditDeleteAndStateCorrectionsRetainRecordedHistory() {
    let root = UUID().uuidString
    let app = launch(root: root)
    defer { app.terminate() }
    createMinimal(app, title: "Corrected history jacket")
    openFirstItem(app)
    us3Tap(app, id: "detail.dropOff")
    us3Enter(app, form: "state.form", id: "state.droppedOffDate", text: "2026-09-30")
    us3Tap(app, id: "state.save", form: "state.form")
    us3Confirm(app)
    us3AddEvent(app, amount: "30", kind: "Money", date: "2026-10-01", note: "Original installment")
    us3AssertValue(app, id: "refund.expected", contains: "Not set")
    us3AssertValue(app, id: "refund.difference", contains: "Not set")
    let editButtons = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "reimbursement.edit."))
    XCTAssertEqual(editButtons.count, 1)
    let editID = editButtons.element(boundBy: 0).identifier
    let deleteID = editID.replacingOccurrences(
      of: "reimbursement.edit.", with: "reimbursement.delete.")
    us3Tap(app, id: editID)
    us3Enter(app, form: "reimbursement.form", id: "reimbursement.amount", text: "20.25")
    us3Choose(app, id: "reimbursement.kind", label: "Store credit", form: "reimbursement.form")
    us3Enter(app, form: "reimbursement.form", id: "reimbursement.date", text: "2026-10-02")
    us3Enter(app, form: "reimbursement.form", id: "reimbursement.note", text: "Corrected credit")
    us3SaveEvent(app)
    us3AssertValue(app, id: "refund.money", contains: "$0.00")
    us3AssertValue(app, id: "refund.credit", contains: "$20.25")
    XCTAssertEqual(editButtons.count, 1)
    XCTAssertEqual(editButtons.element(boundBy: 0).identifier, editID)
    us3Tap(app, id: deleteID)
    XCTAssertTrue(app.buttons["refund.cancelConfirmation"].waitForExistence(timeout: 5))
    us3CancelConfirmation(app, context: .reimbursementDeletion)
    us3AssertValue(app, id: "refund.credit", contains: "$20.25")
    XCTAssertEqual(editButtons.count, 1)
    us3Tap(app, id: "detail.close")
    us3Choose(app, id: "state.outcome", label: "Denied", form: "state.form")
    us3Enter(app, form: "state.form", id: "state.closureNote", text: "Keep recorded credit history")
    us3Tap(app, id: "state.save", form: "state.form")
    us3Confirm(app)
    us3AssertTab(app, id: "tab.history")
    us3Tap(app, id: "detail.correctState")
    us3Choose(app, id: "state.target", label: "To return", form: "state.form")
    us3Tap(app, id: "state.save", form: "state.form")
    us3Confirm(app)
    us3AssertTab(app, id: "tab.toReturn")
    us3AssertValue(app, id: "refund.credit", contains: "$20.25")
    us3AssertValue(app, id: "refund.droppedOffDate", contains: "2026")
    us3Tap(app, id: "detail.keep")
    us3Tap(app, id: "state.save", form: "state.form")
    us3Confirm(app)
    us3AssertTab(app, id: "tab.history")
    us3AssertValue(app, id: "refund.credit", contains: "$20.25")
    app.terminate()
    app.launch()
    us3OpenTabItem(
      app, tab: "tab.history", prefix: "history.item.", title: "Corrected history jacket")
    us3AssertValue(app, id: "refund.credit", contains: "$20.25")
    us3Tap(app, id: deleteID)
    us3Confirm(app, context: .reimbursementDeletion)
    us3AssertValue(app, id: "refund.credit", contains: "$0.00")
    XCTAssertEqual(editButtons.count, 0)
    us3AssertTab(app, id: "tab.history")
    app.terminate()
    app.launch()
    us3OpenTabItem(
      app, tab: "tab.history", prefix: "history.item.", title: "Corrected history jacket")
    XCTAssertEqual(editButtons.count, 0)
    us3AssertValue(app, id: "refund.credit", contains: "$0.00")
  }

  func testExcessConfirmationAndFailedWritePreserveDraftAndCommittedLedger() {
    let root = UUID().uuidString
    let app = launch(root: root)
    defer { app.terminate() }
    openAdd(app)
    enter(app, field: "title", text: "Excess recorded boots")
    enter(app, field: "merchant", text: "Example Store")
    expandOptional(app)
    enter(app, field: "expectedRefund", text: "0")
    save(app)
    openFirstItem(app)
    us3Tap(app, id: "detail.dropOff")
    us3Enter(app, form: "state.form", id: "state.droppedOffDate", text: "2026-10-03")
    us3Tap(app, id: "state.save", form: "state.form")
    us3Confirm(app)
    us3Tap(app, id: "detail.addReimbursement")
    us3Enter(app, form: "reimbursement.form", id: "reimbursement.amount", text: "0")
    us3Tap(app, id: "reimbursement.save", form: "reimbursement.form")
    XCTAssertFalse(app.buttons["refund.confirm"].exists)
    us3AssertFormError(app, form: "reimbursement.form", id: "reimbursement.error")
    us3Enter(app, form: "reimbursement.form", id: "reimbursement.amount", text: "30")
    us3Enter(app, form: "reimbursement.form", id: "reimbursement.date", text: "2026-10-04")
    us3Tap(app, id: "reimbursement.save", form: "reimbursement.form")
    XCTAssertTrue(app.buttons["refund.cancelConfirmation"].waitForExistence(timeout: 5))
    us3CancelConfirmation(app)
    us3Enter(app, form: "reimbursement.form", id: "reimbursement.amount", text: "40")
    us3Choose(app, id: "reimbursement.kind", label: "Store credit", form: "reimbursement.form")
    us3Tap(app, id: "reimbursement.save", form: "reimbursement.form")
    us3Confirm(app)
    us3AssertValue(app, id: "refund.expected", contains: "$0.00")
    us3AssertValue(app, id: "refund.money", contains: "$0.00")
    us3AssertValue(app, id: "refund.credit", contains: "$40.00")
    us3AssertValue(app, id: "refund.difference", contains: "-$40.00")
    app.terminate()
    app.launchArguments = arguments(root: root, extras: ["-rq-test-write-failure"])
    app.launch()
    us3OpenTabItem(app, tab: "tab.waiting", prefix: "waiting.item.", title: "Excess recorded boots")
    let edits = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "reimbursement.edit."))
    XCTAssertEqual(edits.count, 1)
    us3Tap(app, id: edits.element(boundBy: 0).identifier)
    us3Enter(app, form: "reimbursement.form", id: "reimbursement.amount", text: "50")
    us3Tap(app, id: "reimbursement.save", form: "reimbursement.form")
    us3Confirm(app, formMustDismiss: false)
    us3AssertFormError(app, form: "reimbursement.form", id: "reimbursement.error")
    XCTAssertEqual(app.textFields["reimbursement.amount"].value as? String, "50")
    attach(app, name: "US3-write-failure-retained-draft")
    app.terminate()
    app.launchArguments = arguments(root: root)
    app.launch()
    us3OpenTabItem(app, tab: "tab.waiting", prefix: "waiting.item.", title: "Excess recorded boots")
    us3AssertValue(app, id: "refund.credit", contains: "$40.00")
    us3AssertValue(app, id: "refund.difference", contains: "-$40.00")
    XCTAssertEqual(edits.count, 1)
  }

  private func cancelNativeRecoveryShare(_ app: XCUIApplication) -> Bool {
    let activities = app.otherElements.matching(identifier: "ShareSheet.RemoteContainerView")
    let activity = activities.element(boundBy: 0)
    guard activity.waitForExistence(timeout: 5), activities.count == 1 else {
      diagnose(app, name: "Missing-native-share")
      XCTFail("Expected one native sharing activity")
      return false
    }
    let captions = activity.descendants(matching: .any).matching(
      NSPredicate(
        format: "identifier == %@ AND label BEGINSWITH %@",
        "LP.CaptionBar.TopCaption", "ReturnQueue-original-"))
    guard captions.count == 1 else {
      diagnose(app, name: "Missing-original-share-caption")
      XCTFail("Native sharing did not receive the original archive copy")
      return false
    }
    let filename = captions.element(boundBy: 0)
    guard !activity.frame.isEmpty, activity.frame.contains(filename.frame) else {
      diagnose(app, name: "Invalid-native-share-frame")
      XCTFail("Original filename must belong to the visible native activity")
      return false
    }
    attach(app, name: "03-Recovery-native-share")
    // Native sharing uses the simulator's language and its platform-specific cancellation control.
    let closes = activity.descendants(matching: .button).matching(identifier: "header.closeButton")
    if closes.count > 0 {
      guard closes.count == 1, closes.element(boundBy: 0).isHittable else {
        diagnose(app, name: "Ambiguous-native-share-close")
        XCTFail("Expected one reachable native sharing Close button")
        return false
      }
      closes.element(boundBy: 0).tap()
    } else {
      let regions = app.otherElements.matching(identifier: "PopoverDismissRegion")
      guard app.popovers.count == 1, regions.count == 1 else {
        diagnose(app, name: "Missing-native-share-cancellation")
        XCTFail("Expected one native sharing popover and its dismissal region")
        return false
      }
      let popover = app.popovers.element(boundBy: 0)
      let region = regions.element(boundBy: 0)
      let frame = region.frame
      let point = CGPoint(x: frame.midX, y: frame.midY)
      guard region.isHittable, frame.contains(popover.frame),
        popover.frame.contains(activity.frame), popover.frame.contains(filename.frame),
        !frame.isEmpty, frame.contains(point), !popover.frame.contains(point)
      else {
        diagnose(app, name: "Invalid-native-share-dismissal-region")
        XCTFail("Native sharing must have a reachable dismissal area outside its popover")
        return false
      }
      // The unique native region's center lies outside this actual popover.
      region.tap()
    }
    let activityGone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: activity)
    let filenameGone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: filename)
    let dismissal = XCTWaiter.wait(for: [activityGone, filenameGone], timeout: 5)
    if dismissal != .completed { diagnose(app, name: "Native-share-dismissal") }
    XCTAssertEqual(dismissal, .completed, "Native activity and original filename did not dismiss")
    return dismissal == .completed
  }

  private func us3AssertTab(_ app: XCUIApplication, id: String) {
    let tab = us3TabButton(app, id: id)
    XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing real tab \(id)")
    let selected = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "selected == true"), object: tab)
    XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed, "Wrong destination tab")
  }

  private func us3OpenTabItem(_ app: XCUIApplication, tab: String, prefix: String, title: String) {
    let button = us3TabButton(app, id: tab)
    XCTAssertTrue(button.waitForExistence(timeout: 5))
    button.tap()
    let rows = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", prefix, title))
    let row = rows.element(boundBy: 0)
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    XCTAssertEqual(rows.count, 1)
    row.tap()
    XCTAssertTrue(app.buttons["detail.edit"].waitForExistence(timeout: 5))
    us3AssertTab(app, id: tab)
  }

  private enum US3Tab: String, CaseIterable {
    case toReturn = "tab.toReturn"
    case waiting = "tab.waiting"
    case history = "tab.history"

    var label: String {
      switch self {
      case .toReturn: "To return"
      case .waiting: "Waiting for refund"
      case .history: "History"
      }
    }
  }

  private func us3TabButton(_ app: XCUIApplication, id: String) -> XCUIElement {
    guard let expected = US3Tab(rawValue: id) else {
      XCTFail("Unsupported tab identity \(id)")
      return app.tabBars.buttons["Unsupported tab identity"]
    }
    let bars = app.tabBars
    XCTAssertTrue(bars.element(boundBy: 0).waitForExistence(timeout: 5))
    XCTAssertEqual(bars.count, 1, "Expected one real native TabBar")
    let bar = bars.element(boundBy: 0)
    // Cold-launch AX snapshots expose native labels while omitting SwiftUI tab identifiers.
    XCTAssertEqual(bar.buttons.count, US3Tab.allCases.count)
    for tab in US3Tab.allCases {
      XCTAssertEqual(bar.buttons.matching(NSPredicate(format: "label == %@", tab.label)).count, 1)
    }
    let matches = bar.buttons.matching(NSPredicate(format: "label == %@", expected.label))
    XCTAssertEqual(matches.count, 1, "Expected exactly one native \(expected.label) tab")
    let button = matches.element(boundBy: 0)
    XCTAssertTrue(bar.frame.contains(button.frame), "Tab must belong to native TabBar geometry")
    return button
  }

  private func us3AddEvent(
    _ app: XCUIApplication, amount: String, kind: String, date: String, note: String,
    screenshotName: String? = nil
  ) {
    us3Tap(app, id: "detail.addReimbursement")
    if let screenshotName {
      us3CaptureFreshForm(app, form: "reimbursement.form", name: screenshotName)
    }
    us3Enter(app, form: "reimbursement.form", id: "reimbursement.amount", text: amount)
    us3Choose(app, id: "reimbursement.kind", label: kind, form: "reimbursement.form")
    us3Enter(app, form: "reimbursement.form", id: "reimbursement.date", text: date)
    us3Enter(app, form: "reimbursement.form", id: "reimbursement.note", text: note)
    us3SaveEvent(app)
  }

  private func us3CaptureFreshForm(_ app: XCUIApplication, form: String, name: String) {
    XCTAssertTrue(app.collectionViews[form].waitForExistence(timeout: 5))
    XCTAssertFalse(app.keyboards.firstMatch.exists, "Fresh form screenshot must precede input")
    attach(app, name: name)
  }

  private func us3CaptureListAndReopen(
    _ app: XCUIApplication, title: String, prefix: String, recordID: String, name: String
  ) {
    let back = app.navigationBars.buttons[title]
    XCTAssertTrue(back.waitForExistence(timeout: 5))
    back.tap()
    let row = app.buttons["\(prefix).item.\(recordID)"]
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    XCTAssertTrue(row.label.contains("Manual partial sneakers"))
    let rows = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "\(prefix).item."))
    XCTAssertEqual(rows.count, 1)
    let count = app.staticTexts["\(prefix).count"]
    XCTAssertTrue(count.waitForExistence(timeout: 5))
    XCTAssertTrue(count.label.hasPrefix("1 "), "Filtered list count must equal one item")
    attach(app, name: name)
    row.tap()
    XCTAssertTrue(app.buttons["detail.edit"].waitForExistence(timeout: 5))
  }

  private func us3SaveEvent(_ app: XCUIApplication) {
    us3Tap(app, id: "reimbursement.save", form: "reimbursement.form")
    let gone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: app.buttons["reimbursement.save"])
    XCTAssertEqual(
      XCTWaiter.wait(for: [gone], timeout: 5), .completed, "Event did not durably save")
  }

  private enum US3ConfirmationContext {
    case recordedChange, reimbursementDeletion

    var title: String {
      switch self {
      case .recordedChange: "Confirm recorded change"
      case .reimbursementDeletion: "Delete reimbursement?"
      }
    }

    var confirmLabel: String {
      switch self {
      case .recordedChange: "Confirm"
      case .reimbursementDeletion: "Delete reimbursement"
      }
    }
  }

  private func us3Confirm(
    _ app: XCUIApplication, formMustDismiss: Bool = true,
    context: US3ConfirmationContext = .recordedChange
  ) {
    let button = us3ConfirmationButton(
      app, id: "refund.confirm", label: context.confirmLabel, context: context)
    button.tap()
    let gone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: button)
    XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
    if formMustDismiss {
      for id in ["state.save", "reimbursement.save"] {
        let dismissed = XCTNSPredicateExpectation(
          predicate: NSPredicate(format: "exists == false"), object: app.buttons[id])
        XCTAssertEqual(
          XCTWaiter.wait(for: [dismissed], timeout: 5), .completed, "Confirmed form did not commit")
      }
    }
  }

  private func us3CancelConfirmation(
    _ app: XCUIApplication, context: US3ConfirmationContext = .recordedChange
  ) {
    let button = us3ConfirmationButton(
      app, id: "refund.cancelConfirmation", label: "Cancel", context: context)
    button.tap()
    let gone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: button)
    XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
  }

  private func us3ConfirmationButton(
    _ app: XCUIApplication, id: String, label: String, context: US3ConfirmationContext
  )
    -> XCUIElement
  {
    let alerts = app.alerts.matching(NSPredicate(format: "label == %@", context.title))
    XCTAssertTrue(alerts.firstMatch.waitForExistence(timeout: 5))
    XCTAssertEqual(alerts.count, 1, "A confirmation must be one actual dialog")
    let aliases = alerts.element(boundBy: 0).buttons.matching(identifier: id)
    let elements = aliases.allElementsBoundByIndex
    XCTAssertGreaterThan(elements.count, 0, "Missing confirmation action \(id)")
    // The failed xcresult proves SwiftUI exposes nested aliases of one alert button.
    // Validate their meaning and geometry before choosing a match, rather than hiding ambiguity.
    if let first = elements.first {
      for element in elements {
        XCTAssertEqual(element.label, label)
        XCTAssertEqual(element.frame, first.frame, "Matches must be aliases of the same control")
      }
      XCTAssertTrue(first.frame.width > 0 && first.frame.height > 0)
    }
    return aliases.firstMatch
  }

  private func us3AssertValue(_ app: XCUIApplication, id: String, contains text: String) {
    let element = app.staticTexts[id]
    for _ in 0..<12 {
      if element.exists { break }
      us3ScrollDetail(app)
    }
    XCTAssertTrue(element.exists, "Missing value \(id)")
    XCTAssertTrue(element.label.contains(text), "\(id) did not contain \(text): \(element.label)")
  }

  private func us3Tap(_ app: XCUIApplication, id: String, form: String? = nil) {
    let button = app.buttons[id]
    for _ in 0..<16 {
      if button.exists && button.isHittable { break }
      if let form {
        us3ScrollForm(app, form: form, toward: button)
      } else {
        us3ScrollDetail(app, toward: button)
      }
    }
    if !button.exists || !button.isHittable { diagnose(app, name: "US3-unreachable-\(id)") }
    XCTAssertTrue(button.exists && button.isHittable, "Unreachable control \(id)")
    button.tap()
  }

  private func us3Choose(_ app: XCUIApplication, id: String, label: String, form: String) {
    let segmented = app.segmentedControls[id]
    if segmented.exists {
      let choice = segmented.buttons[label]
      for _ in 0..<16 {
        if choice.isHittable { break }
        us3ScrollForm(app, form: form, toward: choice)
      }
      XCTAssertTrue(choice.exists && choice.isHittable, "Missing segmented choice \(label)")
      choice.tap()
      return
    }
    us3Tap(app, id: id, form: form)
    let choice = us3MenuChoice(app, pickerID: id, label: label)
    choice.tap()
  }

  private func us3MenuChoice(_ app: XCUIApplication, pickerID: String, label: String)
    -> XCUIElement
  {
    let expectedOptions: Set<String>
    switch pickerID {
    case "state.target":
      expectedOptions = ["To return", "Waiting for refund", "Closed", "Keeping item"]
    case "state.outcome":
      expectedOptions = [
        "Choose an outcome", "Refund received", "Partial refund", "Denied", "Cancelled",
      ]
    default:
      XCTFail("Unsupported menu picker \(pickerID)")
      return app.buttons["Unsupported menu picker"]
    }
    XCTAssertTrue(expectedOptions.contains(label), "Choice must belong to the expected picker")
    // The actual state-picker popup is a separate unnamed CollectionView of Cell buttons.
    let menus = app.collectionViews.allElementsBoundByIndex.filter { view in
      view.identifier.isEmpty
        && view.cells.buttons.matching(NSPredicate(format: "label == %@", label)).count == 1
    }
    XCTAssertEqual(menus.count, 1, "Expected one actual popup menu, excluding tabs and forms")
    guard let menu = menus.first else { return app.buttons["Missing menu choice"] }
    let options = menu.cells.buttons.allElementsBoundByIndex
    XCTAssertEqual(Set(options.map(\.label)), expectedOptions)
    XCTAssertEqual(options.count, expectedOptions.count)
    let matches = menu.cells.buttons.matching(NSPredicate(format: "label == %@", label))
    XCTAssertEqual(matches.count, 1, "Picker choice must be unique inside its popup")
    let choice = matches.element(boundBy: 0)
    XCTAssertTrue(choice.isHittable, "Actual popup choice must be actionable")
    XCTAssertTrue(menu.frame.contains(choice.frame))
    return choice
  }

  private func us3Enter(_ app: XCUIApplication, form: String, id: String, text: String) {
    func input() -> XCUIElement {
      app.textFields[id].exists ? app.textFields[id] : app.textViews[id]
    }
    for _ in 0..<16 {
      let field = input()
      if field.exists && field.isHittable && us3Viewport(app, form: form).contains(field.frame) {
        break
      }
      us3ScrollForm(app, form: form, toward: field)
    }
    let field = input()
    if !field.exists || !us3Viewport(app, form: form).contains(field.frame) {
      diagnose(app, name: "US3-field-\(id)")
    }
    XCTAssertTrue(
      field.exists && field.isHittable && us3Viewport(app, form: form).contains(field.frame))
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    let old = field.value as? String ?? ""
    let count = old == field.placeholderValue ? 0 : old.count
    if count > 0 {
      field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count))
    }
    if !text.isEmpty { field.typeText(text) }
  }

  private func us3AssertFormError(_ app: XCUIApplication, form: String, id: String) {
    let error = app.staticTexts[id]
    for _ in 0..<16 {
      if error.exists { break }
      us3ScrollForm(app, form: form, toward: error)
    }
    XCTAssertTrue(error.exists, "Failure must retain the form and display an error")
  }

  private func us3Viewport(_ app: XCUIApplication, form: String) -> CGRect {
    let element = app.collectionViews[form]
    XCTAssertTrue(element.exists, "Missing actual Form \(form)")
    let frame = element.frame
    let bars = app.navigationBars.allElementsBoundByIndex.filter {
      $0.isHittable && $0.frame.intersects(frame)
    }
    let top = max(frame.minY, bars.map { $0.frame.maxY }.max() ?? frame.minY) + 16
    let keyboard = app.keyboards.firstMatch
    let bottom = min(frame.maxY - 16, keyboard.exists ? keyboard.frame.minY - 80 : frame.maxY - 16)
    XCTAssertGreaterThan(bottom - top, 60)
    return CGRect(x: frame.minX, y: top, width: frame.width, height: bottom - top)
  }

  private func us3ScrollForm(_ app: XCUIApplication, form: String, toward element: XCUIElement) {
    let viewport = us3Viewport(app, form: form)
    let up = !(element.exists && element.frame.midY < viewport.minY)
    let distance = min(180, viewport.height * 0.5)
    let origin = app.coordinate(withNormalizedOffset: .zero)
    let lower = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.midY + distance * 0.5))
    let upper = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.midY - distance * 0.5))
    (up ? lower : upper).press(forDuration: 0.01, thenDragTo: up ? upper : lower)
  }

  private func us3ScrollDetail(_ app: XCUIApplication, toward element: XCUIElement? = nil) {
    let visible = app.scrollViews.allElementsBoundByIndex.filter { $0.isHittable }
    XCTAssertEqual(visible.count, 1, "Expected the current detail ScrollView")
    guard let scroll = visible.first else { return }
    let frame = scroll.frame
    let up = !(element?.exists == true && element!.frame.midY < frame.minY + 100)
    let origin = app.coordinate(withNormalizedOffset: .zero)
    let lower = origin.withOffset(
      CGVector(dx: frame.midX, dy: min(frame.maxY - 90, frame.midY + 90)))
    let upper = origin.withOffset(
      CGVector(dx: frame.midX, dy: max(frame.minY + 90, frame.midY - 90)))
    (up ? lower : upper).press(forDuration: 0.01, thenDragTo: up ? upper : lower)
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

  private func createTripItem(
    _ app: XCUIApplication, title: String, merchant: String, location: String,
    returnBy: String? = nil
  ) -> String {
    openAdd(app)
    enter(app, field: "title", text: title)
    enter(app, field: "merchant", text: merchant)
    expandOptional(app)
    enter(app, field: "dropOffLocation", text: location)
    if let returnBy { enter(app, field: "returnBy", text: returnBy) }
    save(app)
    let row = itemRows(app).matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    return row.identifier
  }

  private func groupID(_ rowID: String) -> String {
    rowID.replacingOccurrences(of: "queue.item.", with: "queue.group.")
  }

  private func assertTripQueue(
    _ app: XCUIApplication, rows: [String], groups: [String], members: [[String]]
  ) {
    XCTAssertTrue(app.buttons["queue.add"].waitForExistence(timeout: 5))
    XCTAssertEqual(itemRows(app).allElementsBoundByIndex.map(\.identifier), rows)
    let headers = app.staticTexts.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "queue.group."))
    XCTAssertEqual(headers.allElementsBoundByIndex.map(\.identifier), groups)
    XCTAssertEqual(groups.count, members.count)
    for index in groups.indices {
      let header = app.staticTexts[groups[index]]
      for rowID in members[index] {
        XCTAssertGreaterThan(app.buttons[rowID].frame.midY, header.frame.midY)
        if index + 1 < groups.count {
          XCTAssertLessThan(
            app.buttons[rowID].frame.midY, app.staticTexts[groups[index + 1]].frame.midY)
        }
      }
    }
  }

  private func backToQueue(_ app: XCUIApplication) {
    let back = app.navigationBars.buttons["Return Queue"]
    XCTAssertTrue(back.waitForExistence(timeout: 5))
    back.tap()
    XCTAssertTrue(app.buttons["queue.add"].waitForExistence(timeout: 5))
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
