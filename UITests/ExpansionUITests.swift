import XCTest

@MainActor
final class ExpansionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testComparisonPlanPersistsAndDoesNotChangeBase() {
        launch(sample: true)
        selectTab("シミュレーション")
        setPlan(months: "12", goal: "0")
        let original = app.staticTexts["projectionTotal"].label
        tap(app.buttons["comparePlans"])
        XCTAssertTrue(app.buttons["addVariant"].waitForExistence(timeout: 5))
        capture("拡充_01プラン比較")
        tap(app.buttons["addVariant"])
        replace(app.textFields["variantName"], with: "テスト節約")
        tap(app.buttons["支出を月1万円減らす条件を入れる"])
        XCTAssertEqual(app.textFields["variantExpenseAdjustment"].value as? String, "-10000")
        capture("拡充_02比較条件")
        tap(app.buttons["saveVariant"])
        let difference = app.staticTexts["variantDifference.テスト節約"]
        reveal(difference)
        XCTAssertTrue(difference.waitForExistence(timeout: 5))
        let digits = Int(difference.label.filter { $0.isNumber }) ?? 0
        XCTAssertGreaterThan(digits, 120_000, "Saving 10,000 each month adds 120,000 plus growth at sample returns.")
        capture("拡充_03節約の効果")
        relaunchPreservingData()
        selectTab("シミュレーション")
        XCTAssertEqual(app.staticTexts["projectionTotal"].label, original, "Variants must never replace the base plan.")
        tap(app.buttons["comparePlans"])
        tap(app.buttons["editVariant.テスト節約"])
        XCTAssertEqual(app.textFields["variantExpenseAdjustment"].value as? String, "-10000")
        replace(app.textFields["variantName"], with: "キャンセルする編集")
        tap(app.navigationBars.buttons["キャンセル"])
        tap(app.buttons["variantMenu.テスト節約"])
        tap(app.buttons["削除"])
        tap(app.buttons["「テスト節約」を削除"])
        relaunchPreservingData()
        selectTab("シミュレーション")
        XCTAssertEqual(app.staticTexts["projectionTotal"].label, original)
        tap(app.buttons["comparePlans"])
        XCTAssertFalse(app.staticTexts["テスト節約"].exists)
    }

    func testActualBudgetProposalReviewsAppliesAndPersists() {
        launch(sample: true)
        selectTab("家計簿")
        assertMoney("monthlySurplus", equals: 130_000)
        tap(app.buttons["householdInsights"])
        XCTAssertTrue(app.staticTexts["reportMonthlySurplus"].waitForExistence(timeout: 5))
        capture("拡充_04家計レポート")
        tap(app.buttons["openBudgetProposalToolbar"])
        assertMoney("proposalSurplus", equals: 133_000)
        tap(app.segmentedControls["proposalMonths"].buttons["3か月"])
        XCTAssertTrue(app.staticTexts["3か月中 3か月に記録・全12件"].waitForExistence(timeout: 5))
        assertMoney("proposalSurplus", equals: 133_000)
        capture("拡充_05予算の変更確認")
        tap(app.navigationBars.buttons["キャンセル"])
        // Dismissing the proposal is read-only, even though a new budget was calculated.
        tap(app.navigationBars.buttons.element(boundBy: 0))
        assertMoney("monthlySurplus", equals: 130_000)
        tap(app.buttons["householdInsights"])
        tap(app.buttons["openBudgetProposalToolbar"])
        tap(app.buttons["applyActualBudget"])
        let confirmation = app.alerts["この予算案を反映しますか？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        capture("拡充_05b予算反映の確認")
        confirmation.buttons["予算を更新"].firstMatch.tap()
        XCTAssertTrue(app.buttons["openBudgetProposalToolbar"].waitForExistence(timeout: 5))
        relaunchPreservingData()
        selectTab("家計簿")
        assertMoney("monthlySurplus", equals: 133_000)
        capture("拡充_06予算反映後")
        selectTab("資産")
        assertMoney("totalAssets", equals: 4_800_000)
        selectTab("家計簿")
        tap(app.segmentedControls["householdMode"].buttons["日々の記録"])
        assertMoney("actualMonthlyBalance", equals: -4_440)
    }

    private func launch(sample: Bool = false) {
        app.launchArguments = ["--uitesting", "--reset-data", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        if sample { app.launchArguments.append("--sample-data") }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["ホーム"].waitForExistence(timeout: 8))
    }

    private func setPlan(months: String, goal: String) {
        tap(app.buttons["editPlan"])
        replace(app.textFields["planMonths"], with: months)
        replace(app.textFields["planGoal"], with: goal)
        tap(app.buttons["savePlan"])
        XCTAssertTrue(app.buttons["editPlan"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["planValidationError"].exists)
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
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        // Sheets and confirmation dialogs may exist before their presentation
        // animation finishes. Swiping during that animation can dismiss them.
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: element)
        if XCTWaiter.wait(for: [ready], timeout: 3) != .completed {
            reveal(element)
        }
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
