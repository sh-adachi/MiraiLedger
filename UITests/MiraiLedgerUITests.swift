import XCTest

final class MiraiLedgerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testAssetValidationEditingCancellationAndPersistence() {
        launch()
        XCTAssertTrue(app.buttons["loadSample"].waitForExistence(timeout: 8), "A new install must start without fictional financial assets.")
        selectTab("資産")
        assertMoney("totalAssets", equals: 0)
        tap(app.buttons["addAsset"])
        replace(app.textFields["assetName"], with: "テスト資産")
        replace(app.textFields["assetBalance"], with: "")
        tap(app.buttons["saveAsset"])
        let validation = app.alerts["入力を確認してください"]
        XCTAssertTrue(validation.waitForExistence(timeout: 5))
        validation.buttons["OK"].tap()
        XCTAssertEqual(app.textFields["assetName"].value as? String, "テスト資産", "A failed save must preserve the draft.")
        XCTAssertTrue(app.buttons["saveAsset"].exists)

        replace(app.textFields["assetBalance"], with: "1000000")
        replace(app.textFields["assetAnnualReturn"], with: "0")
        tap(app.buttons["saveAsset"])
        XCTAssertTrue(app.buttons["addAsset"].waitForExistence(timeout: 5))
        assertMoney("totalAssets", equals: 1_000_000)

        relaunchPreservingData()
        selectTab("資産")
        assertMoney("totalAssets", equals: 1_000_000)
        tap(app.buttons["テスト資産を編集"])
        XCTAssertEqual(app.textFields["assetName"].value as? String, "テスト資産")
        XCTAssertEqual(app.textFields["assetBalance"].value as? String, "1000000")
        replace(app.textFields["assetBalance"], with: "1200000")
        tap(app.buttons["saveAsset"])
        assertMoney("totalAssets", equals: 1_200_000)

        tap(app.buttons["テスト資産を編集"])
        replace(app.textFields["assetBalance"], with: "999999")
        tap(app.navigationBars.buttons["キャンセル"])
        assertMoney("totalAssets", equals: 1_200_000)
        relaunchPreservingData()
        selectTab("資産")
        assertMoney("totalAssets", equals: 1_200_000)
        tap(app.buttons["テスト資産を編集"])
        XCTAssertEqual(app.textFields["assetBalance"].value as? String, "1200000", "Cancelling an edit must not overwrite the saved valuation.")
        tap(app.navigationBars.buttons["キャンセル"])
        capture("資産_追加と編集の永続化")
    }

    func testBudgetAndJournalPersistWithoutChangingAssetOrProjectionBaseline() {
        launch()
        createZeroReturnAsset()
        selectTab("家計簿")
        addBudget(name: "手取り給与", amount: "300000", income: true)
        addBudget(name: "生活費", amount: "100000", income: false)
        assertMoney("monthlySurplus", equals: 200_000)

        // With no return, the twelve-month result is exactly the current assets
        // plus twelve months of the recurring budget surplus.
        selectTab("シミュレーション")
        setPlan(months: "12", goal: "0")
        assertMoney("projectionTotal", equals: 3_400_000)

        selectTab("家計簿")
        tap(app.segmentedControls["householdMode"].buttons["日々の記録"])
        tap(app.buttons["addTransaction"])
        replace(app.textFields["transactionAmount"], with: "1200")
        replace(noteField, with: "テストの買い物")
        tap(app.buttons["saveTransaction"])
        XCTAssertTrue(app.buttons["addTransaction"].waitForExistence(timeout: 5))
        assertMoney("actualMonthlyBalance", equals: -1_200)
        capture("家計簿_日々の記録")

        selectTab("資産")
        assertMoney("totalAssets", equals: 1_000_000, message: "Historical journal entries must not mutate the asset snapshot.")
        selectTab("シミュレーション")
        assertMoney("projectionTotal", equals: 3_400_000, message: "Only the recurring budget, not historical journal entries, drives the forecast.")

        relaunchPreservingData()
        selectTab("家計簿")
        assertMoney("monthlySurplus", equals: 200_000)
        tap(app.buttons["手取り給与、300,000円、編集"])
        XCTAssertEqual(app.textFields["budgetAmount"].value as? String, "300000")
        tap(app.navigationBars.buttons["キャンセル"])
        tap(app.segmentedControls["householdMode"].buttons["日々の記録"])
        assertMoney("actualMonthlyBalance", equals: -1_200)
        tap(app.staticTexts["テストの買い物"].firstMatch)
        XCTAssertEqual(app.textFields["transactionAmount"].value as? String, "1200")
        XCTAssertEqual(noteField.value as? String, "テストの買い物")
        replace(app.textFields["transactionAmount"], with: "1500")
        tap(app.buttons["saveTransaction"])
        assertMoney("actualMonthlyBalance", equals: -1_500)
        selectTab("資産")
        assertMoney("totalAssets", equals: 1_000_000)

        relaunchPreservingData()
        selectTab("家計簿")
        tap(app.segmentedControls["householdMode"].buttons["日々の記録"])
        assertMoney("actualMonthlyBalance", equals: -1_500)
        tap(app.buttons["前の月"])
        assertMoney("actualMonthlyBalance", equals: 0)
        XCTAssertTrue(app.staticTexts["この月の記録はまだありません"].exists)
        tap(app.buttons["今月へ"])
        assertMoney("actualMonthlyBalance", equals: -1_500)
        selectTab("シミュレーション")
        assertMoney("projectionTotal", equals: 3_400_000)
    }

    func testSampleTourAndPlanPersistence() {
        launch(sample: true)
        assertMoney("currentTotal", equals: 4_800_000)
        XCTAssertTrue(app.staticTexts["サンプルをもとにしたプラン"].exists)
        capture("サンプル_01ホーム")

        selectTab("シミュレーション")
        XCTAssertTrue(app.staticTexts["projectionTotal"].waitForExistence(timeout: 5))
        capture("サンプル_02シミュレーション")
        setPlan(months: "12", goal: "7000000")
        XCTAssertTrue(app.staticTexts["1年経過時の純資産"].waitForExistence(timeout: 5))
        let savedProjection = app.staticTexts["projectionTotal"].label
        capture("サンプル_03一年後の見通し")

        selectTab("資産")
        assertMoney("totalAssets", equals: 4_800_000)
        capture("サンプル_04資産")
        selectTab("家計簿")
        assertMoney("monthlySurplus", equals: 130_000)
        capture("サンプル_05毎月の予算")
        tap(app.segmentedControls["householdMode"].buttons["日々の記録"])
        XCTAssertTrue(app.staticTexts["actualMonthlyBalance"].waitForExistence(timeout: 5))
        capture("サンプル_06日々の記録")
        selectTab("設定")
        XCTAssertTrue(app.buttons["exportBackup"].waitForExistence(timeout: 5))
        capture("サンプル_07設定")

        relaunchPreservingData()
        selectTab("シミュレーション")
        XCTAssertEqual(app.staticTexts["projectionTotal"].label, savedProjection)
        XCTAssertTrue(app.staticTexts["1年経過時の純資産"].exists)
        tap(app.buttons["editPlan"])
        XCTAssertEqual(app.textFields["planMonths"].value as? String, "12")
        XCTAssertEqual(app.textFields["planGoal"].value as? String, "7000000")
        capture("サンプル_08保存したプラン")
        tap(app.navigationBars.buttons["キャンセル"])
    }

    private func launch(sample: Bool = false) {
        app.launchArguments = ["--uitesting", "--reset-data", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        if sample { app.launchArguments.append("--sample-data") }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["ホーム"].waitForExistence(timeout: 8))
    }

    private func createZeroReturnAsset() {
        selectTab("資産")
        tap(app.buttons["addAsset"])
        replace(app.textFields["assetName"], with: "テスト資産")
        replace(app.textFields["assetBalance"], with: "1000000")
        replace(app.textFields["assetAnnualReturn"], with: "0")
        tap(app.buttons["saveAsset"])
        assertMoney("totalAssets", equals: 1_000_000)
    }

    private func addBudget(name: String, amount: String, income: Bool) {
        tap(app.buttons["addBudget"])
        tap(app.segmentedControls["budgetKind"].buttons[income ? "収入" : "支出"])
        replace(app.textFields["budgetName"], with: name)
        replace(app.textFields["budgetAmount"], with: amount)
        tap(app.buttons["saveBudget"])
        XCTAssertTrue(app.buttons["addBudget"].waitForExistence(timeout: 5))
    }

    private func setPlan(months: String, goal: String) {
        tap(app.buttons["editPlan"])
        replace(app.textFields["planMonths"], with: months)
        replace(app.textFields["planGoal"], with: goal)
        tap(app.buttons["savePlan"])
        XCTAssertTrue(app.buttons["editPlan"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["planValidationError"].exists)
    }

    private var noteField: XCUIElement {
        let textField = app.textFields["transactionNote"]
        return textField.exists ? textField : app.textViews["transactionNote"]
    }

    private func selectTab(_ title: String) {
        tap(app.tabBars.buttons[title])
    }

    private func assertMoney(_ identifier: String, equals expected: Int, message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        let element = app.staticTexts[identifier]
        reveal(element)
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing amount: \(identifier)", file: file, line: line)
        let normalized = element.label.replacingOccurrences(of: "−", with: "-")
        let value = Int(normalized.filter { $0.isNumber || $0 == "-" })
        XCTAssertEqual(value, expected, message.isEmpty ? "Unexpected amount in \(identifier)" : message, file: file, line: line)
    }

    private func replace(_ field: XCUIElement, with value: String) {
        tap(field)
        let current = field.value as? String ?? ""
        // Put the caret after the existing content before removing it. This is
        // important for right-aligned numeric fields when their text is short.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + value)
        if !value.isEmpty { XCTAssertEqual(field.value as? String, value) }
        dismissKeyboardIfAvailable()
    }

    private func dismissKeyboardIfAvailable() {
        let done = app.toolbars.buttons["完了"].firstMatch
        if done.exists && done.isHittable { done.tap() }
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<5 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        for _ in 0..<5 {
            if element.exists && element.isHittable { return }
            app.swipeDown()
        }
    }

    private func tap(_ element: XCUIElement) {
        reveal(element)
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable, "Element is not tappable: \(element)")
        element.tap()
    }

    private func relaunchPreservingData() {
        app.terminate()
        app.launchArguments.removeAll { $0 == "--reset-data" || $0 == "--sample-data" }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["ホーム"].waitForExistence(timeout: 8))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
