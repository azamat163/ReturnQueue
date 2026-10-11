import Foundation
import XCTest

@MainActor
final class DataBackupsTests: XCTestCase {
  func testNativeSavedBackupRestoresRichLedgerAndResetsAllCoincidentIDPaths() {
    continueAfterFailure = false
    let app = XCUIApplication()
    let root = UUID().uuidString
    attachRoot(root, name: "US4-rich-native-roundtrip-root")
    app.launchArguments = arguments(root)
    app.launch()
    defer { app.terminate() }
    let rich = createRichReturn(app)
    showList(app, tab: "tab.toReturn", title: "Return Queue")
    let planned = createReturn(app, title: "Queue sibling")
    let kept = createReturn(app, title: "History sibling")
    openItem(app, prefix: "queue", id: kept)
    backupTap(app, id: "detail.keep")
    XCTAssertTrue(app.collectionViews["state.form"].waitForExistence(timeout: 5))
    backupTap(app, id: "state.save", form: "state.form")
    backupConfirm(app)
    backupAssertTab(app, id: "tab.history")
    app.terminate()
    app.launchArguments = arguments(root) + ["-rq-test-backup-fixtures"]
    app.launch()
    openData(app)
    let filename = exportAndSaveNative(app, root: root)
    closeData(app)
    selectTab(app, id: "tab.waiting")
    openItem(app, prefix: "waiting", id: rich.id)
    app.buttons["detail.edit"].tap()
    XCTAssertTrue(app.collectionViews["editor.form"].waitForExistence(timeout: 5))
    backupEnter(app, form: "editor.form", id: "editor.title", text: "Changed after export")
    expandOptional(app)
    backupEnter(app, form: "editor.form", id: "editor.notes", text: "Later local note")
    saveEditor(app)
    selectTab(app, id: "tab.history")
    openItem(app, prefix: "history", id: kept)
    selectTab(app, id: "tab.toReturn")
    openItem(app, prefix: "queue", id: planned)
    selectTab(app, id: "tab.waiting")
    XCTAssertTrue(app.buttons["detail.edit"].isHittable)
    assertDetailText(app, text: "Changed after export")
    selectTab(app, id: "tab.history")
    XCTAssertTrue(app.buttons["detail.edit"].isHittable)
    selectTab(app, id: "tab.toReturn")
    XCTAssertTrue(app.buttons["detail.edit"].isHittable)
    capture(app, name: "US4-all-three-detail-paths-populated-before-replacement")
    openData(app)
    cancelActualPicker(app)
    XCTAssertFalse(app.staticTexts["restore.preview"].exists)
    XCTAssertTrue(app.buttons["data.restore"].isEnabled)
    selectNativeOwnedFile(app, root: root, filename: filename)
    assertPreview(app, returns: 3, events: 2, current: 3)
    tapDataButton(app, id: "restore.replace")
    dialogAction(app, title: "Replace current data?", id: "restore.confirmCancel", label: "Cancel")
    XCTAssertTrue(app.staticTexts["restore.preview"].exists)
    tapDataButton(app, id: "restore.cancel")
    waitGone(app.staticTexts["restore.preview"])
    closeData(app)
    XCTAssertTrue(app.buttons["detail.edit"].isHittable)
    selectTab(app, id: "tab.waiting")
    XCTAssertTrue(app.buttons["detail.edit"].isHittable)
    assertDetailText(app, text: "Changed after export")
    assertDetailText(app, text: "Later local note")
    selectTab(app, id: "tab.history")
    XCTAssertTrue(app.buttons["detail.edit"].isHittable)
    selectTab(app, id: "tab.toReturn")
    openData(app)
    selectNativeOwnedFile(app, root: root, filename: filename)
    assertPreview(app, returns: 3, events: 2, current: 3)
    tapDataButton(app, id: "restore.exportCurrent")
    cancelNativeOwnedShare(app, prefix: "ReturnQueue-backup-")
    waitEnabled(app.buttons["restore.exportCurrent"])
    XCTAssertTrue(app.buttons["data.close"].isEnabled)
    assertPreview(app, returns: 3, events: 2, current: 3)
    replaceData(app)
    assertAllLists(app, planned: planned, waiting: rich.id, history: kept)
    selectTab(app, id: "tab.waiting")
    openItem(app, prefix: "waiting", id: rich.id)
    assertRichLedger(app, events: rich.events)
    openData(app)
    selectNativeOwnedFile(app, root: root, filename: filename)
    assertPreview(app, returns: 3, events: 2, current: 3)
    replaceData(app)
    assertAllLists(app, planned: planned, waiting: rich.id, history: kept)
    app.terminate()
    app.launch()
    assertAllLists(app, planned: planned, waiting: rich.id, history: kept)
    selectTab(app, id: "tab.waiting")
    openItem(app, prefix: "waiting", id: rich.id)
    assertRichLedger(app, events: rich.events)
    capture(app, name: "US4-rich-restored-ledger-after-repeat-and-relaunch")
  }

  func testDeleteReturnCancellationAndConfirmedOwnerDeletionPreserveOtherSavedRecord() {
    continueAfterFailure = false
    let app = XCUIApplication()
    let root = UUID().uuidString
    attachRoot(root, name: "US4-single-delete-root")
    app.launchArguments = arguments(root)
    app.launch()
    defer { app.terminate() }
    let owner = createReturn(app, title: "Delete owner shoes")
    openItem(app, prefix: "queue", id: owner)
    backupAddEvent(
      app, amount: "12.50", kind: "Money", date: "2026-10-04", note: "Owner-only payment")
    showList(app, tab: "tab.toReturn", title: "Return Queue")
    let remaining = createReturn(app, title: "Remaining coat")
    openItem(app, prefix: "queue", id: owner)
    revealDeleteReturn(app)
    dialogAction(app, title: "Delete return?", id: "delete.returnCancel", label: "Cancel")
    XCTAssertTrue(app.buttons["detail.edit"].isHittable)
    backupAssertValue(app, id: "refund.money", contains: "$12.50")
    revealDeleteReturn(app)
    dialogAction(app, title: "Delete return?", id: "delete.returnConfirm", label: "Delete return")
    assertList(app, tab: "tab.toReturn", prefix: "queue", title: "Return Queue", id: remaining)
    XCTAssertFalse(app.buttons["queue.item.\(owner)"].exists)
    app.terminate()
    app.launch()
    assertList(app, tab: "tab.toReturn", prefix: "queue", title: "Return Queue", id: remaining)
    openItem(app, prefix: "queue", id: remaining)
    assertDetailText(app, text: "Remaining coat")
    XCTAssertEqual(
      app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "reimbursement.edit."))
        .count, 0)
    backupAssertValue(app, id: "refund.money", contains: "$0.00")
    capture(app, name: "US4-single-delete-retained-other-record-after-relaunch")
  }

  func testDeleteAllCancellationKeepsLedgerThenConfirmedEmptyArchiveSurvivesRelaunch() {
    continueAfterFailure = false
    let app = XCUIApplication()
    let root = UUID().uuidString
    attachRoot(root, name: "US4-all-delete-root")
    app.launchArguments = arguments(root)
    app.launch()
    defer { app.terminate() }
    let owner = createReturn(app, title: "All-delete owner")
    openItem(app, prefix: "queue", id: owner)
    backupAddEvent(
      app, amount: "12.50", kind: "Store credit", date: "2026-10-05", note: "All-delete credit")
    showList(app, tab: "tab.toReturn", title: "Return Queue")
    let other = createReturn(app, title: "All-delete sibling")
    openData(app)
    tapDataButton(app, id: "data.deleteAll")
    dialogAction(app, title: "Delete all data?", id: "delete.allCancel", label: "Cancel")
    closeData(app)
    XCTAssertTrue(app.buttons["queue.item.\(owner)"].exists)
    XCTAssertTrue(app.buttons["queue.item.\(other)"].exists)
    openItem(app, prefix: "queue", id: owner)
    backupAssertValue(app, id: "refund.credit", contains: "$12.50")
    openData(app)
    tapDataButton(app, id: "data.deleteAll")
    dialogAction(app, title: "Delete all data?", id: "delete.allConfirm", label: "Delete all data")
    waitGone(app.buttons["data.close"])
    assertReadyEmpty(app)
    app.terminate()
    app.launch()
    assertReadyEmpty(app)
    capture(app, name: "US4-all-delete-canonical-empty-after-relaunch")
  }

  func testNativeRejectedAndFailedChangesExplicitCorruptRepairAndConfirmedEmptyReplacement() {
    continueAfterFailure = false
    let app = XCUIApplication()
    defer { app.terminate() }
    let failedRoot = UUID().uuidString
    attachRoot(failedRoot, name: "US4-cancel-invalid-writefail-preserved-root")
    app.launchArguments = arguments(failedRoot)
    app.launch()
    let failedID = createReturn(app, title: "Preserved failure baseline")
    app.terminate()
    app.launchArguments = arguments(failedRoot) + ["-rq-test-backup-fixtures"]
    app.launch()
    openData(app)
    cancelActualPicker(app)
    XCTAssertFalse(app.staticTexts["restore.preview"].exists)
    selectNativeOwnedFile(app, root: failedRoot, filename: "Invalid-return-backup.json")
    assertDataError(app, contains: "invalid")
    XCTAssertFalse(app.staticTexts["restore.preview"].exists)
    capture(app, name: "US4-native-invalid-archive-preserves-current-record")
    closeData(app)
    XCTAssertTrue(app.buttons["queue.item.\(failedID)"].exists)
    app.terminate()
    app.launchArguments =
      arguments(failedRoot) + ["-rq-test-backup-fixtures", "-rq-test-write-failure"]
    app.launch()
    openData(app)
    selectNativeOwnedFile(app, root: failedRoot, filename: "Saved-return-backup.json")
    assertPreview(app, returns: 1, events: 0, current: 1)
    tapDataButton(app, id: "restore.replace")
    dialogAction(app, title: "Replace current data?", id: "restore.confirmCancel", label: "Cancel")
    XCTAssertTrue(app.staticTexts["restore.preview"].exists)
    tapDataButton(app, id: "restore.replace")
    dialogAction(
      app, title: "Replace current data?", id: "restore.confirm", label: "Replace current data")
    assertDataError(app, contains: "Could not save")
    XCTAssertTrue(app.staticTexts["restore.preview"].exists)
    XCTAssertFalse(app.staticTexts["data.success"].exists)
    capture(app, name: "US4-failed-replacement-retains-preview-and-old-record")
    tapDataButton(app, id: "restore.cancel")
    waitGone(app.staticTexts["restore.preview"])
    tapDataButton(app, id: "data.deleteAll")
    dialogAction(app, title: "Delete all data?", id: "delete.allConfirm", label: "Delete all data")
    assertDataError(app, contains: "Could not save")
    XCTAssertFalse(app.staticTexts["data.success"].exists)
    closeData(app)
    openItem(app, prefix: "queue", id: failedID)
    revealDeleteReturn(app)
    dialogAction(app, title: "Delete return?", id: "delete.returnConfirm", label: "Delete return")
    XCTAssertTrue(app.staticTexts["delete.returnError"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["detail.edit"].isEnabled)
    capture(app, name: "US4-failed-single-and-all-delete-preserve-actual-record")
    app.terminate()
    app.launchArguments = arguments(failedRoot)
    app.launch()
    XCTAssertTrue(app.buttons["queue.item.\(failedID)"].waitForExistence(timeout: 5))
    app.terminate()

    let repairRoot = UUID().uuidString
    attachRoot(repairRoot, name: "US4-unreadable-explicit-repair-root")
    app.launchArguments = arguments(repairRoot)
    app.launch()
    let repairedID = createReturn(app, title: "Explicitly repaired shoes")
    app.terminate()
    app.launchArguments = arguments(repairRoot) + ["-rq-test-backup-fixtures", "-rq-test-corrupt"]
    app.launch()
    XCTAssertTrue(app.buttons["load.retry"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["queue.add"].isEnabled)
    openData(app)
    XCTAssertFalse(app.buttons["data.export"].isEnabled)
    XCTAssertFalse(app.buttons["data.deleteAll"].isEnabled)
    tapDataButton(app, id: "data.exportOriginal")
    XCTAssertTrue(
      app.alerts.staticTexts.matching(
        NSPredicate(format: "label CONTAINS %@", "personal information")
      ).element(boundBy: 0).waitForExistence(timeout: 5))
    dialogAction(
      app, title: "Export original unreadable data?", id: "data.originalCancel", label: "Cancel")
    XCTAssertFalse(app.otherElements["ShareSheet.RemoteContainerView"].exists)
    tapDataButton(app, id: "data.exportOriginal")
    dialogAction(
      app, title: "Export original unreadable data?", id: "data.originalConfirm",
      label: "Export original data")
    cancelNativeOwnedShare(app, prefix: "ReturnQueue-original-")
    waitEnabled(app.buttons["data.exportOriginal"])
    XCTAssertTrue(app.buttons["data.close"].isEnabled)
    XCTAssertFalse(app.buttons["data.export"].isEnabled)
    selectNativeOwnedFile(app, root: repairRoot, filename: "Saved-return-backup.json")
    assertPreview(app, returns: 1, events: 0, current: nil)
    tapDataButton(app, id: "restore.replace")
    dialogAction(app, title: "Replace current data?", id: "restore.confirmCancel", label: "Cancel")
    XCTAssertTrue(app.staticTexts["restore.preview"].exists)
    XCTAssertFalse(app.buttons["data.export"].isEnabled)
    capture(app, name: "US4-unreadable-unknown-current-count-before-explicit-replacement")
    replaceData(app)
    XCTAssertTrue(app.buttons["queue.item.\(repairedID)"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["load.retry"].exists)
    app.terminate()
    app.launchArguments = arguments(repairRoot)
    app.launch()
    XCTAssertTrue(app.buttons["queue.item.\(repairedID)"].waitForExistence(timeout: 5))
    app.terminate()

    let emptyRoot = UUID().uuidString
    attachRoot(emptyRoot, name: "US4-confirmed-empty-replacement-root")
    app.launchArguments = arguments(emptyRoot)
    app.launch()
    let removedID = createReturn(app, title: "Empty replacement baseline")
    app.terminate()
    app.launchArguments = arguments(emptyRoot) + ["-rq-test-backup-fixtures"]
    app.launch()
    openData(app)
    selectNativeOwnedFile(app, root: emptyRoot, filename: "Empty-return-backup.json")
    assertPreview(app, returns: 0, events: 0, current: 1)
    tapDataButton(app, id: "restore.replace")
    dialogAction(app, title: "Replace current data?", id: "restore.confirmCancel", label: "Cancel")
    XCTAssertTrue(app.staticTexts["restore.preview"].exists)
    closeData(app)
    XCTAssertTrue(app.buttons["queue.item.\(removedID)"].exists)
    openData(app)
    selectNativeOwnedFile(app, root: emptyRoot, filename: "Empty-return-backup.json")
    assertPreview(app, returns: 0, events: 0, current: 1)
    replaceData(app)
    assertReadyEmpty(app)
    openData(app)
    selectNativeOwnedFile(app, root: emptyRoot, filename: "Empty-return-backup.json")
    assertPreview(app, returns: 0, events: 0, current: 0)
    tapDataButton(app, id: "restore.replace")
    dialogAction(app, title: "Replace current data?", id: "restore.confirmCancel", label: "Cancel")
    XCTAssertTrue(app.staticTexts["restore.preview"].exists)
    XCTAssertFalse(app.staticTexts["data.success"].exists)
    capture(app, name: "US4-ready-empty-still-requires-explicit-confirmation")
    replaceData(app)
    assertReadyEmpty(app)
    app.terminate()
    app.launchArguments = arguments(emptyRoot)
    app.launch()
    assertReadyEmpty(app)
  }

  private struct RichRecord {
    let id: String
    let events: [String]
  }

  private func attachRoot(_ root: String, name: String) {
    let attachment = XCTAttachment(string: "Isolated DEBUG UI test root: \(root)")
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func capture(_ app: XCUIApplication, name: String) {
    let hierarchy = XCTAttachment(string: app.debugDescription)
    hierarchy.name = "\(name)-hierarchy"
    hierarchy.lifetime = .keepAlways
    add(hierarchy)
    let screen = XCTAttachment(screenshot: app.screenshot())
    screen.name = "\(name)-screen"
    screen.lifetime = .keepAlways
    add(screen)
  }

  private func attach(_ app: XCUIApplication, name: String) { capture(app, name: name) }
  private func diagnose(_ app: XCUIApplication, name: String) { capture(app, name: name) }

  private func waitGone(_ element: XCUIElement) {
    let gone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: element)
    XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
  }

  private func waitEnabled(_ element: XCUIElement) {
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == true AND hittable == true AND enabled == true"),
      object: element)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
  }

  @discardableResult
  private func createReturn(_ app: XCUIApplication, title: String) -> String {
    waitEnabled(app.buttons["queue.add"])
    app.buttons["queue.add"].tap()
    XCTAssertTrue(app.collectionViews["editor.form"].waitForExistence(timeout: 5))
    backupEnter(app, form: "editor.form", id: "editor.title", text: title)
    backupEnter(app, form: "editor.form", id: "editor.merchant", text: "Example Store")
    saveEditor(app)
    let rows = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "queue.item.", title))
    XCTAssertTrue(rows.element(boundBy: 0).waitForExistence(timeout: 5))
    XCTAssertEqual(rows.count, 1)
    return rows.element(boundBy: 0).identifier.replacingOccurrences(of: "queue.item.", with: "")
  }

  private func saveEditor(_ app: XCUIApplication) {
    waitEnabled(app.buttons["editor.save"])
    app.buttons["editor.save"].tap()
    waitGone(app.buttons["editor.save"])
  }

  private func expandOptional(_ app: XCUIApplication) {
    let disclosure = app.staticTexts["editor.optional"]
    XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
    for _ in 0..<8 {
      if disclosure.isHittable
        && backupViewport(app, form: "editor.form").contains(disclosure.frame)
      {
        break
      }
      backupScrollForm(app, form: "editor.form", toward: disclosure)
    }
    XCTAssertTrue(disclosure.isHittable)
    disclosure.tap()
  }

  private func createRichReturn(_ app: XCUIApplication) -> RichRecord {
    let id = createReturn(app, title: "Backup ledger shoes")
    openItem(app, prefix: "queue", id: id)
    app.buttons["detail.edit"].tap()
    XCTAssertTrue(app.collectionViews["editor.form"].waitForExistence(timeout: 5))
    expandOptional(app)
    let values = [
      ("dropOffLocation", "Downtown counter"), ("returnBy", "2026-10-21"),
      ("purchaseDate", "2026-09-30"), ("expectedRefundDate", "2026-10-20"),
      ("purchasePrice", "150"), ("expectedRefund", "100"),
      ("policyReference", "Manual merchant policy"), ("notes", "Original saved note"),
    ]
    for (field, text) in values {
      backupEnter(app, form: "editor.form", id: "editor.\(field)", text: text)
    }
    saveEditor(app)
    backupTap(app, id: "detail.dropOff")
    XCTAssertTrue(app.collectionViews["state.form"].waitForExistence(timeout: 5))
    backupEnter(app, form: "state.form", id: "state.droppedOffDate", text: "2026-10-03")
    backupEnter(app, form: "state.form", id: "state.expectedRefundDate", text: "2026-10-20")
    backupTap(app, id: "state.save", form: "state.form")
    backupConfirm(app)
    backupAssertTab(app, id: "tab.waiting")
    backupAddEvent(
      app, amount: "50", kind: "Money", date: "2026-10-04", note: "Original cash payment")
    backupAddEvent(
      app, amount: "30", kind: "Store credit", date: "2026-10-05", note: "Original store credit")
    let cash = app.buttons.matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "reimbursement.edit.", "Money"))
    let credit = app.buttons.matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "reimbursement.edit.",
        "Store credit"))
    XCTAssertEqual(cash.count, 1)
    XCTAssertEqual(credit.count, 1)
    let events = [cash.element(boundBy: 0).identifier, credit.element(boundBy: 0).identifier]
    let identity = XCTAttachment(
      string: "Rich return UUID: \(id)\nEvents: \(events.joined(separator: ", "))")
    identity.name = "US4-rich-original-record-and-event-identities"
    identity.lifetime = .keepAlways
    add(identity)
    assertRichLedger(app, events: events)
    return RichRecord(id: id, events: events)
  }

  private func assertRichLedger(_ app: XCUIApplication, events: [String]) {
    XCTAssertEqual(events.count, 2)
    backupAssertValue(app, id: "refund.money", contains: "$50.00")
    backupAssertValue(app, id: "refund.credit", contains: "$30.00")
    backupAssertValue(app, id: "refund.expected", contains: "$100.00")
    backupAssertValue(app, id: "refund.difference", contains: "$20.00")
    backupAssertValue(app, id: "refund.droppedOffDate", contains: "Oct 3, 2026")
    let edits = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "reimbursement.edit."))
    XCTAssertEqual(Set(edits.allElementsBoundByIndex.map(\.identifier)), Set(events))
    for (index, day) in ["Oct 4, 2026", "Oct 5, 2026"].enumerated() {
      let dateID = events[index].replacingOccurrences(
        of: "reimbursement.edit.", with: "reimbursement.item.")
      backupAssertValue(app, id: dateID, contains: day)
    }
    XCTAssertTrue(app.buttons[events[0]].label.contains("Money"))
    XCTAssertTrue(app.buttons[events[0]].label.contains("$50.00"))
    XCTAssertTrue(app.buttons[events[1]].label.contains("Store credit"))
    XCTAssertTrue(app.buttons[events[1]].label.contains("$30.00"))
    for text in [
      "Backup ledger shoes", "Downtown counter", "Oct 21, 2026", "Sep 30, 2026", "Oct 20, 2026",
      "Original cash payment", "Original store credit", "Original saved note",
      "Manual merchant policy", "$150.00",
    ] {
      assertDetailText(app, text: text)
    }
  }

  private func assertDetailText(_ app: XCUIApplication, text: String) {
    let matches = app.staticTexts.matching(NSPredicate(format: "label == %@", text))
    for _ in 0..<12 {
      if matches.count > 0 { break }
      backupScrollDetail(app)
    }
    XCTAssertEqual(matches.count, 1, "Expected the exact retained detail value \(text)")
  }

  private func selectTab(_ app: XCUIApplication, id: String) {
    let button = backupTabButton(app, id: id)
    XCTAssertTrue(button.isHittable)
    if !button.isSelected { button.tap() }
    backupAssertTab(app, id: id)
  }

  private func showList(_ app: XCUIApplication, tab: String, title: String) {
    selectTab(app, id: tab)
    if app.buttons["detail.edit"].exists && app.buttons["detail.edit"].isHittable {
      let back = app.navigationBars.buttons.matching(NSPredicate(format: "label == %@", title))
      XCTAssertEqual(back.count, 1)
      XCTAssertTrue(back.element(boundBy: 0).isHittable)
      back.element(boundBy: 0).tap()
      waitGone(app.buttons["detail.edit"])
    }
  }

  private func openItem(_ app: XCUIApplication, prefix: String, id: String) {
    let rows = app.buttons.matching(identifier: "\(prefix).item.\(id)")
    XCTAssertTrue(rows.element(boundBy: 0).waitForExistence(timeout: 5))
    XCTAssertEqual(rows.count, 1)
    XCTAssertTrue(rows.element(boundBy: 0).isHittable)
    rows.element(boundBy: 0).tap()
    XCTAssertTrue(app.buttons["detail.edit"].waitForExistence(timeout: 5))
  }

  private func assertList(
    _ app: XCUIApplication, tab: String, prefix: String, title: String, id: String
  ) {
    selectTab(app, id: tab)
    let lists = app.collectionViews.matching(identifier: "\(prefix).list")
    XCTAssertTrue(lists.element(boundBy: 0).waitForExistence(timeout: 5))
    XCTAssertEqual(lists.count, 1)
    let list = lists.element(boundBy: 0)
    let rows = list.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "\(prefix).item."))
    XCTAssertEqual(rows.count, 1)
    XCTAssertEqual(rows.element(boundBy: 0).identifier, "\(prefix).item.\(id)")
    waitEnabled(rows.element(boundBy: 0))
    XCTAssertTrue(list.frame.contains(rows.element(boundBy: 0).frame))
    XCTAssertFalse(app.buttons["detail.edit"].exists, "Restored stack must show its list")
    let bar = app.navigationBars.matching(identifier: title)
    XCTAssertEqual(bar.count, 1)
    XCTAssertEqual(
      bar.element(boundBy: 0).buttons.matching(NSPredicate(format: "label == %@", title)).count, 0)
  }

  private func assertAllLists(
    _ app: XCUIApplication, planned: String, waiting: String, history: String
  ) {
    assertList(app, tab: "tab.toReturn", prefix: "queue", title: "Return Queue", id: planned)
    assertList(app, tab: "tab.waiting", prefix: "waiting", title: "Waiting for refund", id: waiting)
    assertList(app, tab: "tab.history", prefix: "history", title: "History", id: history)
    capture(app, name: "US4-all-three-restored-stacks-at-lists")
  }

  private func openData(_ app: XCUIApplication) {
    waitEnabled(app.buttons["data.open"])
    app.buttons["data.open"].tap()
    XCTAssertTrue(app.collectionViews["data.form"].waitForExistence(timeout: 5))
  }

  private func closeData(_ app: XCUIApplication) {
    waitEnabled(app.buttons["data.close"])
    app.buttons["data.close"].tap()
    waitGone(app.buttons["data.close"])
  }

  private func revealDataElement(_ app: XCUIApplication, element: XCUIElement) {
    let form = app.collectionViews["data.form"]
    XCTAssertTrue(form.exists)
    for _ in 0..<8 {
      if element.exists { break }
      form.swipeUp()
    }
    XCTAssertTrue(element.exists)
  }

  private func assertPreview(_ app: XCUIApplication, returns: Int, events: Int, current: Int?) {
    let title = app.staticTexts["restore.preview"]
    revealDataElement(app, element: title)
    XCTAssertTrue(title.exists)
    for (id, label) in [
      ("restore.returnCount", "\(returns) returns"),
      ("restore.eventCount", "\(events) reimbursements"),
    ] {
      let value = app.staticTexts[id]
      revealDataElement(app, element: value)
      XCTAssertEqual(value.label, label)
    }
    let currentLabel =
      current.map { "\($0) returns currently on this iPhone." }
      ?? "Current return count is unknown because saved data could not be read."
    let currentText = app.staticTexts.matching(NSPredicate(format: "label == %@", currentLabel))
    revealDataElement(app, element: currentText.element(boundBy: 0))
    XCTAssertEqual(currentText.count, 1)
    let warning = app.staticTexts["This replaces the returns currently on this iPhone."]
    revealDataElement(app, element: warning)
    capture(app, name: "US4-ready-restore-preview-\(returns)-returns-\(events)-events")
  }

  private func assertDataError(_ app: XCUIApplication, contains text: String) {
    let error = app.staticTexts["data.error"]
    revealDataElement(app, element: error)
    let matches = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == true AND label CONTAINS %@", text), object: error)
    XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 5), .completed)
  }

  private func dialogAction(_ app: XCUIApplication, title: String, id: String, label: String) {
    let alerts = app.alerts.matching(NSPredicate(format: "label == %@", title))
    XCTAssertTrue(alerts.element(boundBy: 0).waitForExistence(timeout: 5))
    XCTAssertEqual(alerts.count, 1)
    let alert = alerts.element(boundBy: 0)
    let aliases = alert.buttons.matching(identifier: id).allElementsBoundByIndex
    XCTAssertGreaterThan(aliases.count, 0)
    guard let action = aliases.first else { return }
    for alias in aliases {
      XCTAssertEqual(alias.label, label)
      XCTAssertEqual(
        alias.frame, action.frame, "Only identical representations of one control may alias")
    }
    XCTAssertFalse(action.frame.isEmpty)
    XCTAssertTrue(alert.frame.contains(action.frame))
    XCTAssertTrue(action.isHittable && action.isEnabled)
    capture(app, name: "US4-actual-confirmation-\(id)")
    action.tap()
    waitGone(alert)
  }

  private func replaceData(_ app: XCUIApplication) {
    tapDataButton(app, id: "restore.replace")
    dialogAction(
      app, title: "Replace current data?", id: "restore.confirm", label: "Replace current data")
    waitGone(app.buttons["data.close"])
  }

  private func cancelActualPicker(_ app: XCUIApplication) {
    tapDataButton(app, id: "data.restore")
    let bars = app.navigationBars.matching(
      identifier: "FullDocumentManagerViewControllerNavigationBar")
    XCTAssertTrue(bars.element(boundBy: 0).waitForExistence(timeout: 5))
    XCTAssertEqual(bars.count, 1)
    let bar = bars.element(boundBy: 0)
    // A remembered Browse leaf has only Back. The observed Recents root exposes Cancel.
    let nativeTabs = app.tabBars.matching(identifier: "DOC.browsingModeTabBar")
    XCTAssertTrue(nativeTabs.element(boundBy: 0).waitForExistence(timeout: 5))
    XCTAssertEqual(nativeTabs.count, 1)
    let nativeTabBar = nativeTabs.element(boundBy: 0)
    let recentsButtons = nativeTabBar.buttons.matching(
      NSPredicate(format: "label == %@", "Recents"))
    let recents = recentsButtons.element(boundBy: 0)
    waitEnabled(recents)
    XCTAssertEqual(recentsButtons.count, 1)
    XCTAssertTrue(nativeTabBar.frame.contains(recents.frame))
    if !recents.isSelected {
      recents.tap()
      let selected = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "selected == true"), object: recents)
      XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
    }
    let recentsRoots = app.otherElements.matching(
      identifier:
        "DOC.browsingRoot Source: com.apple.DocumentManager.RecentDocuments, Title: Recents")
    XCTAssertTrue(recentsRoots.element(boundBy: 0).waitForExistence(timeout: 5))
    XCTAssertEqual(recentsRoots.count, 1)
    XCTAssertTrue(recents.isSelected)
    let cancels = bar.buttons.matching(NSPredicate(format: "label == %@", "Cancel"))
    let cancel = cancels.element(boundBy: 0)
    waitEnabled(cancel)
    capture(app, name: "US4-actual-native-picker-cancel-ready")
    XCTAssertEqual(cancels.count, 1)
    XCTAssertTrue(cancel.isHittable && bar.frame.contains(cancel.frame))
    XCTAssertFalse(app.buttons["data.close"].isEnabled)
    cancel.tap()
    waitGone(bar)
    waitEnabled(app.buttons["data.restore"])
    XCTAssertTrue(app.buttons["data.close"].isEnabled)
  }

  private func revealDeleteReturn(_ app: XCUIApplication) {
    let button = app.buttons["detail.deleteReturn"]
    if !button.exists || !button.isHittable {
      capture(app, name: "US4-actual-delete-action-before-detail-scroll")
    }
    backupTap(app, id: "detail.deleteReturn")
  }

  private func assertReadyEmpty(_ app: XCUIApplication) {
    waitEnabled(app.buttons["queue.add"])
    XCTAssertEqual(
      app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "queue.item.")).count, 0)
    XCTAssertTrue(app.staticTexts["No returns yet"].exists)
    XCTAssertFalse(app.buttons["load.retry"].exists)
  }

  private func exportAndSaveNative(_ app: XCUIApplication, root: String) -> String {
    tapDataButton(app, id: "data.export")
    let activities = app.otherElements.matching(identifier: "ShareSheet.RemoteContainerView")
    let activityReady = activities.element(boundBy: 0).waitForExistence(timeout: 5)
    let shareHierarchy = XCTAttachment(string: app.debugDescription)
    shareHierarchy.name = "US4-actual-validated-native-share-hierarchy"
    shareHierarchy.lifetime = .keepAlways
    add(shareHierarchy)
    let shareScreen = XCTAttachment(screenshot: app.screenshot())
    shareScreen.name = "US4-actual-validated-native-share-screen"
    shareScreen.lifetime = .keepAlways
    add(shareScreen)
    XCTAssertTrue(activityReady, "The Data sheet did not present its real native export activity")
    XCTAssertEqual(activities.count, 1)
    let activity = activities.element(boundBy: 0)
    let captions = activity.descendants(matching: .any).matching(
      NSPredicate(
        format: "identifier == %@ AND label BEGINSWITH %@",
        "LP.CaptionBar.TopCaption", "ReturnQueue-backup-"))
    XCTAssertEqual(captions.count, 1)
    XCTAssertTrue(activity.frame.contains(captions.element(boundBy: 0).frame))
    let exportIdentity = XCTAttachment(
      string: "Owned root: \(root)\nNative export caption: \(captions.element(boundBy: 0).label)")
    exportIdentity.name = "US4-native-export-identity"
    exportIdentity.lifetime = .keepAlways
    add(exportIdentity)
    // The actual native activity uses Russian independently of the English app language.
    let nativeSaveLabel = "Сохранить в\u{00A0}Файлах"
    let activityCollections = activity.collectionViews.matching(
      identifier: "activityCollectionView")
    XCTAssertEqual(activityCollections.count, 1)
    let saveCells = activityCollections.element(boundBy: 0).cells
      .matching(identifier: "actionGroupCell")
      .containing(.staticText, identifier: nativeSaveLabel)
    XCTAssertEqual(saveCells.count, 1, "Expected the actually observed native Save to Files action")
    let saveCell = saveCells.element(boundBy: 0)
    let saveCaptions = saveCell.staticTexts.matching(
      NSPredicate(format: "identifier == %@ AND label == %@", "cellTitleLabel", nativeSaveLabel))
    XCTAssertEqual(saveCaptions.count, 1)
    XCTAssertTrue(saveCell.isHittable)
    XCTAssertTrue(activity.frame.contains(saveCell.frame))
    XCTAssertTrue(saveCell.frame.contains(saveCaptions.element(boundBy: 0).frame))
    saveCell.tap()
    let saveBars = app.navigationBars.matching(
      NSPredicate(
        format: "identifier != %@ AND identifier != %@ AND identifier != %@",
        "Return Queue", "Data & backups", "UIActivityContentView"))
    let saveReady = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == true AND hittable == true"),
      object: saveBars.element(boundBy: 0))
    let savePresented = XCTWaiter.wait(for: [saveReady], timeout: 10) == .completed
    let saveHierarchy = XCTAttachment(string: app.debugDescription)
    saveHierarchy.name = "US4-native-Save-to-Files-picker-hierarchy"
    saveHierarchy.lifetime = .keepAlways
    add(saveHierarchy)
    let saveScreen = XCTAttachment(screenshot: app.screenshot())
    saveScreen.name = "US4-native-Save-to-Files-picker-screen"
    saveScreen.lifetime = .keepAlways
    add(saveScreen)
    XCTAssertTrue(savePresented, "The observed native Save action did not present its picker")
    let saveFileViews = app.collectionViews.matching(identifier: "File View")
    let saveContentReady = saveFileViews.element(boundBy: 0).waitForExistence(timeout: 5)
    let filenameFields = app.textFields.matching(identifier: "DOCPicker.filenameTextField")
    let filenameReady = filenameFields.element(boundBy: 0).waitForExistence(timeout: 5)
    let loadedSaveHierarchy = XCTAttachment(string: app.debugDescription)
    loadedSaveHierarchy.name = "US4-native-Save-loaded-content-hierarchy"
    loadedSaveHierarchy.lifetime = .keepAlways
    add(loadedSaveHierarchy)
    XCTAssertTrue(
      saveContentReady, "The native save picker did not load its actual file collection")
    XCTAssertTrue(filenameReady)
    XCTAssertEqual(saveFileViews.count, 1)
    XCTAssertEqual(filenameFields.count, 1)
    navigateNativeOwnedFolder(app, root: root)
    let saveOwnedTitle = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
      .buttons.matching(NSPredicate(format: "label == %@", "\(root), Actions Menu"))
    let saveOwnedReady = saveOwnedTitle.element(boundBy: 0).waitForExistence(timeout: 5)
    let finalSaveHierarchy = XCTAttachment(string: app.debugDescription)
    finalSaveHierarchy.name = "US4-native-Save-owned-destination-hierarchy"
    finalSaveHierarchy.lifetime = .keepAlways
    add(finalSaveHierarchy)
    let finalSaveScreen = XCTAttachment(screenshot: app.screenshot())
    finalSaveScreen.name = "US4-native-Save-owned-destination-screen"
    finalSaveScreen.lifetime = .keepAlways
    add(finalSaveScreen)
    let filenameIdentity = XCTAttachment(
      string:
        "Actual native filename value: \(String(describing: filenameFields.element(boundBy: 0).value))"
    )
    filenameIdentity.name = "US4-native-Save-filename-value"
    filenameIdentity.lifetime = .keepAlways
    add(filenameIdentity)
    XCTAssertTrue(saveOwnedReady)
    XCTAssertEqual(saveOwnedTitle.count, 1)
    let nativeFilename = captions.element(boundBy: 0).label
    XCTAssertEqual(filenameFields.element(boundBy: 0).value as? String, nativeFilename)
    let actualSaveBar = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
    let saveButtons = actualSaveBar.buttons.matching(NSPredicate(format: "label == %@", "Save"))
    XCTAssertEqual(saveButtons.count, 1)
    let actualSave = saveButtons.element(boundBy: 0)
    XCTAssertTrue(actualSave.isHittable && actualSave.isEnabled)
    XCTAssertTrue(actualSaveBar.frame.contains(actualSave.frame))
    actualSave.tap()
    let activityGone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: activity)
    let captionGone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: captions.element(boundBy: 0))
    let savePickerGone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: filenameFields.element(boundBy: 0))
    XCTAssertEqual(
      XCTWaiter.wait(for: [activityGone, captionGone, savePickerGone], timeout: 10), .completed)
    let exportEnabled = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == true AND hittable == true AND enabled == true"),
      object: app.buttons["data.export"])
    XCTAssertEqual(XCTWaiter.wait(for: [exportEnabled], timeout: 10), .completed)
    let cleanupHierarchy = XCTAttachment(string: app.debugDescription)
    cleanupHierarchy.name = "US4-after-native-Save-actual-dismissal-cleanup"
    cleanupHierarchy.lifetime = .keepAlways
    add(cleanupHierarchy)
    XCTAssertTrue(app.buttons["data.close"].isEnabled)
    return "\(nativeFilename).json"
  }

  private func selectNativeOwnedFile(_ app: XCUIApplication, root: String, filename: String) {
    tapDataButton(app, id: "data.restore")
    let bars = app.navigationBars.matching(
      identifier: "FullDocumentManagerViewControllerNavigationBar")
    XCTAssertTrue(bars.element(boundBy: 0).waitForExistence(timeout: 5))
    XCTAssertEqual(bars.count, 1)
    let bar = bars.element(boundBy: 0)
    let nativeTabs = app.tabBars.matching(identifier: "DOC.browsingModeTabBar")
    XCTAssertEqual(nativeTabs.count, 1)
    let browseButtons = nativeTabs.element(boundBy: 0).buttons.matching(
      NSPredicate(format: "label == %@", "Browse"))
    XCTAssertEqual(browseButtons.count, 1)
    let browse = browseButtons.element(boundBy: 0)
    if !browse.isSelected {
      XCTAssertTrue(browse.isHittable)
      browse.tap()
      let selected = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "selected == true"), object: browse)
      XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
    }
    let localContent = app.descendants(matching: .any).matching(
      NSPredicate(
        format: "identifier == %@ OR identifier BEGINSWITH %@", "Browse View",
        "DOC.browsingRoot Source: com.apple.FileProvider.LocalStorage, Title:"))
    XCTAssertTrue(localContent.element(boundBy: 0).waitForExistence(timeout: 5))
    XCTAssertEqual(localContent.count, 1, "Expected actual local Files or its Locations sidebar")
    let sidebars = app.collectionViews.matching(identifier: "Browse View")
    if sidebars.count == 1 {
      let sidebar = sidebars.element(boundBy: 0)
      let phoneCells = sidebar.cells.matching(identifier: "DOC.sidebar.item.On My iPhone")
      XCTAssertEqual(phoneCells.count, 1)
      let phone = phoneCells.element(boundBy: 0)
      XCTAssertTrue(phone.isHittable && sidebar.frame.contains(phone.frame))
      phone.tap()
    }
    navigateNativeOwnedFolder(app, root: root)
    let fileViews = app.collectionViews.matching(identifier: "File View")
    XCTAssertEqual(fileViews.count, 1)
    let files = fileViews.element(boundBy: 0)
    let matches = files.cells.matching(identifier: "\(filename), json")
    XCTAssertTrue(matches.element(boundBy: 0).waitForExistence(timeout: 5))
    XCTAssertEqual(matches.count, 1)
    let file = matches.element(boundBy: 0)
    XCTAssertTrue(file.isHittable && file.isEnabled && files.frame.contains(file.frame))
    file.tap()
    let gone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: bar)
    XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
  }

  private func navigateNativeOwnedFolder(_ app: XCUIApplication, root: String) {
    let bars = app.navigationBars.matching(
      identifier: "FullDocumentManagerViewControllerNavigationBar")
    XCTAssertTrue(bars.element(boundBy: 0).waitForExistence(timeout: 5))
    XCTAssertEqual(bars.count, 1)
    let bar = bars.element(boundBy: 0)
    let fileViews = app.collectionViews.matching(identifier: "File View")
    XCTAssertTrue(fileViews.element(boundBy: 0).waitForExistence(timeout: 5))
    XCTAssertEqual(fileViews.count, 1)
    let files = fileViews.element(boundBy: 0)
    let knownTitles = bar.descendants(matching: .any).matching(
      NSPredicate(
        format: "(elementType == %d AND label == %@) OR (elementType == %d AND label ENDSWITH %@)",
        XCUIElement.ElementType.staticText.rawValue, "On My iPhone",
        XCUIElement.ElementType.button.rawValue, ", Actions Menu"))
    XCTAssertTrue(knownTitles.element(boundBy: 0).waitForExistence(timeout: 5))
    XCTAssertEqual(knownTitles.count, 1, "Expected one actually observed local folder title")
    let phoneTitle = bar.staticTexts.matching(NSPredicate(format: "label == %@", "On My iPhone"))
    if phoneTitle.count == 1 {
      let apps = files.cells.matching(identifier: "Return Queue, Container")
      XCTAssertEqual(apps.count, 1)
      let appFolder = apps.element(boundBy: 0)
      XCTAssertTrue(appFolder.isHittable && files.frame.contains(appFolder.frame))
      appFolder.tap()
      let loadedAppTitle = bar.buttons.matching(
        NSPredicate(format: "label == %@", "Return Queue, Actions Menu"))
      XCTAssertTrue(loadedAppTitle.element(boundBy: 0).waitForExistence(timeout: 5))
      XCTAssertEqual(loadedAppTitle.count, 1)
    }
    let appTitle = bar.buttons.matching(
      NSPredicate(format: "label == %@", "Return Queue, Actions Menu"))
    if appTitle.count == 1 {
      let fixtures = files.cells.matching(identifier: "ReturnQueueFixtures, Folder")
      XCTAssertTrue(fixtures.element(boundBy: 0).waitForExistence(timeout: 5))
      XCTAssertEqual(fixtures.count, 1)
      let fixture = fixtures.element(boundBy: 0)
      XCTAssertTrue(fixture.isHittable && files.frame.contains(fixture.frame))
      fixture.tap()
      let loadedFixtureTitle = bar.buttons.matching(
        NSPredicate(format: "label == %@", "ReturnQueueFixtures, Actions Menu"))
      XCTAssertTrue(loadedFixtureTitle.element(boundBy: 0).waitForExistence(timeout: 5))
      XCTAssertEqual(loadedFixtureTitle.count, 1)
    }
    // Files can remember a different isolated leaf from a previous journey in this process.
    let menus = bar.buttons.matching(NSPredicate(format: "label ENDSWITH %@", ", Actions Menu"))
    if menus.count == 1 {
      let currentName = String(menus.element(boundBy: 0).label.dropLast(", Actions Menu".count))
      if UUID(uuidString: currentName) != nil, currentName != root {
        let backs = bar.buttons.matching(identifier: "BackButton")
        XCTAssertEqual(backs.count, 1)
        let back = backs.element(boundBy: 0)
        XCTAssertEqual(back.label, "ReturnQueueFixtures")
        XCTAssertTrue(back.isHittable && bar.frame.contains(back.frame))
        back.tap()
        let parent = bar.buttons.matching(
          NSPredicate(format: "label == %@", "ReturnQueueFixtures, Actions Menu"))
        XCTAssertTrue(parent.element(boundBy: 0).waitForExistence(timeout: 5))
        XCTAssertEqual(parent.count, 1)
      }
    }
    let fixtureTitle = bar.buttons.matching(
      NSPredicate(format: "label == %@", "ReturnQueueFixtures, Actions Menu"))
    if fixtureTitle.count == 1 {
      let ownFolders = files.cells.containing(.staticText, identifier: root)
      for _ in 0..<12 {
        let folder = ownFolders.element(boundBy: 0)
        if folder.exists && folder.isHittable && files.frame.contains(folder.frame) { break }
        if folder.exists && folder.frame.midY < files.frame.minY + 100 {
          files.swipeDown()
        } else {
          files.swipeUp()
        }
      }
      XCTAssertEqual(ownFolders.count, 1)
      let own = ownFolders.element(boundBy: 0)
      var previousFrame: CGRect?
      var stableObservations = 0
      let stableFolder = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          guard own.exists, own.isHittable else {
            previousFrame = nil
            stableObservations = 0
            return false
          }
          let frame = own.frame
          guard !frame.isEmpty, files.frame.contains(frame) else {
            previousFrame = nil
            stableObservations = 0
            return false
          }
          stableObservations = previousFrame == frame ? stableObservations + 1 : 1
          previousFrame = frame
          return stableObservations >= 3
        }, object: own)
      // Actual failed-run callbacks cost about 3 seconds each, including XCTest AX diagnostics.
      // Three observations need about 9 seconds; allow 3 seconds for the final observation.
      guard XCTWaiter.wait(for: [stableFolder], timeout: 12) == .completed else {
        capture(app, name: "US4-native-owned-folder-did-not-settle")
        XCTFail("The unique owned folder must be stable and hittable before one tap")
        return
      }
      XCTAssertTrue(own.isHittable && files.frame.contains(own.frame))
      own.tap()
    }
    let ownTitle = bar.buttons.matching(
      NSPredicate(format: "label == %@", "\(root), Actions Menu"))
    XCTAssertTrue(ownTitle.element(boundBy: 0).waitForExistence(timeout: 5))
    XCTAssertEqual(ownTitle.count, 1, "File selection must occur in this explicitly owned UUID")
  }

  private func tapDataButton(_ app: XCUIApplication, id: String) {
    let form = app.collectionViews["data.form"]
    XCTAssertTrue(form.waitForExistence(timeout: 5))
    let button = app.buttons[id]
    for _ in 0..<8 {
      if button.exists && button.isHittable { break }
      let above =
        button.exists ? button.frame.midY < form.frame.minY + 100 : id == "data.export"
      if above {
        form.swipeDown()
      } else {
        form.swipeUp()
      }
    }
    XCTAssertTrue(button.exists && button.isHittable, "Unreachable Data action \(id)")
    XCTAssertTrue(button.isEnabled)
    button.tap()
  }

  @discardableResult
  private func cancelNativeOwnedShare(_ app: XCUIApplication, prefix: String) -> Bool {
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
        "LP.CaptionBar.TopCaption", prefix))
    guard captions.count == 1 else {
      diagnose(app, name: "Missing-original-share-caption")
      XCTFail("Native sharing did not receive this owned archive copy")
      return false
    }
    let filename = captions.element(boundBy: 0)
    guard !activity.frame.isEmpty, activity.frame.contains(filename.frame) else {
      diagnose(app, name: "Invalid-native-share-frame")
      XCTFail("Export filename must belong to the visible native activity")
      return false
    }
    XCTAssertFalse(app.buttons["data.close"].isEnabled)
    attach(app, name: "US4-actual-native-owned-share-before-cancellation")
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

  private func backupAssertTab(_ app: XCUIApplication, id: String) {
    let tab = backupTabButton(app, id: id)
    XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing real tab \(id)")
    let selected = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "selected == true"), object: tab)
    XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed, "Wrong destination tab")
  }

  private enum BackupTab: String, CaseIterable {
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

  private func backupTabButton(_ app: XCUIApplication, id: String) -> XCUIElement {
    guard let expected = BackupTab(rawValue: id) else {
      XCTFail("Unsupported tab identity \(id)")
      return app.tabBars.buttons["Unsupported tab identity"]
    }
    let bars = app.tabBars
    XCTAssertTrue(bars.element(boundBy: 0).waitForExistence(timeout: 5))
    XCTAssertEqual(bars.count, 1, "Expected one real native TabBar")
    let bar = bars.element(boundBy: 0)
    // Cold-launch AX snapshots expose native labels while omitting SwiftUI tab identifiers.
    XCTAssertEqual(bar.buttons.count, BackupTab.allCases.count)
    for tab in BackupTab.allCases {
      XCTAssertEqual(bar.buttons.matching(NSPredicate(format: "label == %@", tab.label)).count, 1)
    }
    let matches = bar.buttons.matching(NSPredicate(format: "label == %@", expected.label))
    XCTAssertEqual(matches.count, 1, "Expected exactly one native \(expected.label) tab")
    let button = matches.element(boundBy: 0)
    XCTAssertTrue(bar.frame.contains(button.frame), "Tab must belong to native TabBar geometry")
    return button
  }

  private func backupAddEvent(
    _ app: XCUIApplication, amount: String, kind: String, date: String, note: String,
    screenshotName: String? = nil
  ) {
    backupTap(app, id: "detail.addReimbursement")
    if let screenshotName {
      backupCaptureFreshForm(app, form: "reimbursement.form", name: screenshotName)
    }
    backupEnter(app, form: "reimbursement.form", id: "reimbursement.amount", text: amount)
    backupChoose(app, id: "reimbursement.kind", label: kind, form: "reimbursement.form")
    backupEnter(app, form: "reimbursement.form", id: "reimbursement.date", text: date)
    backupEnter(app, form: "reimbursement.form", id: "reimbursement.note", text: note)
    backupSaveEvent(app)
  }

  private func backupCaptureFreshForm(_ app: XCUIApplication, form: String, name: String) {
    XCTAssertTrue(app.collectionViews[form].waitForExistence(timeout: 5))
    XCTAssertFalse(app.keyboards.firstMatch.exists, "Fresh form screenshot must precede input")
    attach(app, name: name)
  }

  private func backupSaveEvent(_ app: XCUIApplication) {
    backupTap(app, id: "reimbursement.save", form: "reimbursement.form")
    let gone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: app.buttons["reimbursement.save"])
    XCTAssertEqual(
      XCTWaiter.wait(for: [gone], timeout: 5), .completed, "Event did not durably save")
  }

  private enum BackupConfirmationContext {
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

  private func backupConfirm(
    _ app: XCUIApplication, formMustDismiss: Bool = true,
    context: BackupConfirmationContext = .recordedChange
  ) {
    let button = backupConfirmationButton(
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

  private func backupCancelConfirmation(
    _ app: XCUIApplication, context: BackupConfirmationContext = .recordedChange
  ) {
    let button = backupConfirmationButton(
      app, id: "refund.cancelConfirmation", label: "Cancel", context: context)
    button.tap()
    let gone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: button)
    XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
  }

  private func backupConfirmationButton(
    _ app: XCUIApplication, id: String, label: String, context: BackupConfirmationContext
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

  private func backupAssertValue(_ app: XCUIApplication, id: String, contains text: String) {
    let element = app.staticTexts[id]
    for _ in 0..<12 {
      if element.exists { break }
      backupScrollDetail(app)
    }
    XCTAssertTrue(element.exists, "Missing value \(id)")
    XCTAssertTrue(element.label.contains(text), "\(id) did not contain \(text): \(element.label)")
  }

  private func backupTap(_ app: XCUIApplication, id: String, form: String? = nil) {
    let button = app.buttons[id]
    for _ in 0..<16 {
      if button.exists && button.isHittable { break }
      if let form {
        backupScrollForm(app, form: form, toward: button)
      } else {
        backupScrollDetail(app, toward: button)
      }
    }
    if !button.exists || !button.isHittable { diagnose(app, name: "Backup-unreachable-\(id)") }
    XCTAssertTrue(button.exists && button.isHittable, "Unreachable control \(id)")
    button.tap()
  }

  private func backupChoose(_ app: XCUIApplication, id: String, label: String, form: String) {
    let segmented = app.segmentedControls[id]
    if segmented.exists {
      let choice = segmented.buttons[label]
      for _ in 0..<16 {
        if choice.isHittable { break }
        backupScrollForm(app, form: form, toward: choice)
      }
      XCTAssertTrue(choice.exists && choice.isHittable, "Missing segmented choice \(label)")
      choice.tap()
      return
    }
    backupTap(app, id: id, form: form)
    let choice = backupMenuChoice(app, pickerID: id, label: label)
    choice.tap()
  }

  private func backupMenuChoice(_ app: XCUIApplication, pickerID: String, label: String)
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

  private func backupEnter(_ app: XCUIApplication, form: String, id: String, text: String) {
    func input() -> XCUIElement {
      app.textFields[id].exists ? app.textFields[id] : app.textViews[id]
    }
    for _ in 0..<16 {
      let field = input()
      if field.exists && field.isHittable && backupViewport(app, form: form).contains(field.frame) {
        break
      }
      backupScrollForm(app, form: form, toward: field)
    }
    let field = input()
    if !field.exists || !backupViewport(app, form: form).contains(field.frame) {
      diagnose(app, name: "Backup-field-\(id)")
    }
    XCTAssertTrue(
      field.exists && field.isHittable && backupViewport(app, form: form).contains(field.frame))
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    let old = field.value as? String ?? ""
    let count = old == field.placeholderValue ? 0 : old.count
    if count > 0 {
      field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count))
    }
    if !text.isEmpty { field.typeText(text) }
  }

  private func backupAssertFormError(_ app: XCUIApplication, form: String, id: String) {
    let error = app.staticTexts[id]
    for _ in 0..<16 {
      if error.exists { break }
      backupScrollForm(app, form: form, toward: error)
    }
    XCTAssertTrue(error.exists, "Failure must retain the form and display an error")
  }

  private func backupViewport(_ app: XCUIApplication, form: String) -> CGRect {
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

  private func backupScrollForm(_ app: XCUIApplication, form: String, toward element: XCUIElement) {
    let viewport = backupViewport(app, form: form)
    let up = !(element.exists && element.frame.midY < viewport.minY)
    let distance = min(180, viewport.height * 0.5)
    let origin = app.coordinate(withNormalizedOffset: .zero)
    let lower = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.midY + distance * 0.5))
    let upper = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.midY - distance * 0.5))
    (up ? lower : upper).press(forDuration: 0.01, thenDragTo: up ? upper : lower)
  }

  private func backupScrollDetail(_ app: XCUIApplication, toward element: XCUIElement? = nil) {
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

  private func arguments(_ root: String) -> [String] {
    ["-rq-ui-testing", "-rq-test-root", root, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
  }
}
