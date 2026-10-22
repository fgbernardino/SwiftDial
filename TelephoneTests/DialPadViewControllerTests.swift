import AppKit
import XCTest

@MainActor
final class DialPadViewControllerTests: XCTestCase {
    private func buttons(in view: NSView) -> [NSButton] {
        view.subviews.flatMap { child -> [NSButton] in
            if let button = child as? NSButton { return [button] }
            return buttons(in: child)
        }
    }

    func testPrefilledDialPadWaitsForExplicitDial() {
        var result: String?
        let sut = DialPadViewController(destination: "11999998888") { result = $0 }
        let stack = sut.view.subviews.first as! NSStackView
        let field = stack.arrangedSubviews.first as! NSTextField
        XCTAssertEqual(field.stringValue, "11999998888")
        XCTAssertNil(result)
        field.stringValue = "11999998889"
        buttons(in: sut.view).last!.performClick(nil)
        XCTAssertEqual(result, "11999998889")
    }

    func testClickDigitsAndBackspaceThenDial() {
        var result: String?
        let sut = DialPadViewController(destination: "11") { result = $0 }
        let keys = buttons(in: sut.view)
        for symbol in ["8", "⌫", "9", "*", "#", "+"] {
            keys.first { $0.title == symbol }!.performClick(nil)
        }
        XCTAssertNil(result)
        keys.last!.performClick(nil)
        XCTAssertEqual(result, "119*#+")
    }

    func testCorrectedHistoryNumberDoesNotRepeatRoutingPrefix() throws {
        let plan = try DialPlan("<0:043>x.")
        var result: String?
        let sut = DialPadViewController(destination: "0434133334444") {
            result = try? plan.apply(to: $0, fromHistory: true)
        }
        let keys = buttons(in: sut.view)
        keys.first { $0.title == "⌫" }!.performClick(nil)
        keys.first { $0.title == "5" }!.performClick(nil)
        XCTAssertNil(result)
        keys.last!.performClick(nil)
        XCTAssertEqual(result, "0434133334445")
        XCTAssertEqual(try plan.apply(to: "0434133334445"), "043434133334445")
    }

    func testEmptyDestinationDoesNotDial() {
        var didDial = false
        let sut = DialPadViewController(destination: "") { _ in didDial = true }
        let keys = buttons(in: sut.view)
        keys.first { $0.title == "⌫" }!.performClick(nil)
        keys.last!.performClick(nil)
        XCTAssertFalse(didDial)
    }

    func testKeyboardInputUsesSameDialAction() {
        var result: String?
        let sut = DialPadViewController(destination: "") { result = $0 }
        let stack = sut.view.subviews.first as! NSStackView
        let field = stack.arrangedSubviews.first as! NSTextField
        field.stringValue = " 12345 "
        NSApp.sendAction(field.action!, to: field.target, from: field)
        XCTAssertEqual(result, "12345")
    }
}
