import XCTest

final class DialPlanTests: XCTestCase {
    private let example = "xxx|xxxxxxxx|xxxxxxxxx|0800x.|0300x.|<0:043>x."

    func testUserPlanAndFinalDot() throws {
        let plan = try DialPlan(example)
        for (input, expected) in ["118": "118", "33334444": "33334444", "999998888": "999998888",
                                  "08001234567": "08001234567", "03003376786": "03003376786",
                                  "04133334444": "0434133334444", "0": "043", "0800": "0800"] {
            XCTAssertEqual(try plan.apply(to: input), expected)
        }
        for number in ["12", "1234", "11999998888", "+5511999998888", ""] {
            XCTAssertThrowsError(try plan.apply(to: number), number)
        }
    }

    func testOrderFullMatchInsertionDeletionRangesAndLiteralRepetition() throws {
        XCTAssertEqual(try DialPlan("xxx|<0:043>x.").apply(to: "012"), "012")
        XCTAssertEqual(try DialPlan("(<+:00>x.|x.)").apply(to: "+5511999998888"), "005511999998888")
        XCTAssertEqual(try DialPlan("<:1>xxxxxxxxxx").apply(to: "2125551234"), "12125551234")
        XCTAssertEqual(try DialPlan("<0:>x.").apply(to: "0123"), "123")
        XCTAssertEqual(try DialPlan("[16-9*]xx").apply(to: "*18"), "*18")
        XCTAssertThrowsError(try DialPlan("[2-9]xx").apply(to: "118"))
        XCTAssertEqual(try DialPlan("01.").apply(to: "01111"), "01111")
        XCTAssertEqual(try DialPlan("01.").apply(to: "0"), "0")
        XCTAssertThrowsError(try DialPlan("xxx").apply(to: "1111"))
        XCTAssertEqual(try DialPlan("x.x.9").apply(to: "1239"), "1239")
        XCTAssertEqual(try DialPlan("[*]x.[*]x.").apply(to: "*21*118#"), "*21*118#")
    }

    func testHistoryAppliesPlanWithoutRepeatingPrefix() throws {
        let plan = try DialPlan(example)
        for (raw, routed) in [("04133334444", "0434133334444"), ("118", "118"),
                              ("08001234567", "08001234567"), ("03003376786", "03003376786")] {
            XCTAssertEqual(try plan.apply(to: raw, fromHistory: true), routed)
            XCTAssertEqual(try plan.apply(to: routed, fromHistory: true), routed)
        }
        // Manual dialing retains the original MicroSIP rule semantics.
        XCTAssertEqual(try plan.apply(to: "0434133334444"), "043434133334444")
        XCTAssertThrowsError(try plan.apply(to: "1234", fromHistory: true))
        XCTAssertEqual(try plan.apply(to: "04312", fromHistory: true), "0434312")
    }

    func testHistoryRecognizesOnlyOutputsOfTheOrderedPlan() throws {
        let insertion = try DialPlan("<:55>xxxxxxxxxxx")
        XCTAssertEqual(try insertion.apply(to: "11999998888", fromHistory: true), "5511999998888")
        XCTAssertEqual(try insertion.apply(to: "5511999998888", fromHistory: true), "5511999998888")
        XCTAssertThrowsError(try insertion.apply(to: "55118", fromHistory: true))
        let ordered = try DialPlan("0x.|<0:043>x.")
        XCTAssertEqual(try ordered.apply(to: "0431234", fromHistory: true), "0431234")
        let shadowed = try DialPlan("<0:9>x.|<0:043>x.")
        XCTAssertEqual(try shadowed.apply(to: "0431234", fromHistory: true), "9431234")
        let deletion = try DialPlan("<0:>xxxxxxxx")
        XCTAssertEqual(try deletion.apply(to: "33334444", fromHistory: true), "33334444")
        XCTAssertEqual(try DialPlan("").apply(to: "1234", fromHistory: true), "1234")
    }

    func testOriginalNumberRecoveryVerifiesRuleOrderAndAmbiguity() throws {
        XCTAssertEqual(try DialPlan(example).originalNumber(for: "0434133334444"), "04133334444")
        XCTAssertEqual(try DialPlan("<:55>xxxxxxxxxxx").originalNumber(for: "5511999998888"), "11999998888")
        XCTAssertEqual(try DialPlan("<0:9>xx|<1:9>xx").originalNumber(for: "918"), nil)
        XCTAssertNil(try DialPlan("xxx|<0:043>x.").originalNumber(for: "043"))
        XCTAssertEqual(try DialPlan("0x.|<0:043>x.").originalNumber(for: "0431234"), "0431234")
        XCTAssertEqual(try DialPlan("").originalNumber(for: "118"), "118")
        XCTAssertNil(try DialPlan(example).originalNumber(for: "sip:118@example.com"))
    }

    func testHistoryRecognizesPlusSubstitutedPlanOutputs() throws {
        let plan = try DialPlan("<0:+>x.")
        XCTAssertEqual(try plan.apply(to: "0123"), "+123")
        XCTAssertEqual(try plan.apply(to: "00123", fromHistory: true, plusSubstitution: "00"), "00123")
        XCTAssertEqual(try plan.apply(to: "123", fromHistory: true, plusSubstitution: ""), "123")
        // Manual calls and accounts without plus substitution retain the plan's normal behavior.
        XCTAssertEqual(try plan.apply(to: "00123", plusSubstitution: "00"), "+0123")
        XCTAssertEqual(try plan.apply(to: "00123", fromHistory: true), "+0123")
        XCTAssertEqual(try DialPlan("+x.").apply(to: "00123", fromHistory: true, plusSubstitution: "00"), "00123")
        // A later rule that produces plus must not bypass an earlier matching rule.
        XCTAssertEqual(try DialPlan("<0:9>x.|<0:+>x.").apply(to: "00123", fromHistory: true, plusSubstitution: "00"), "90123")
        XCTAssertThrowsError(try plan.apply(to: "99123", fromHistory: true, plusSubstitution: "00"))
    }

    func testInvalidPlansFailClosed() {
        for text in ["xxx|", "|xxx", ".x", "x..", "[9-2]", "[]", "[", "<0>", "<0:1", "<:>",
                     "<0:1>.", "(xxx", "xxx)", "x{3}", "<0:sip:>", String(repeating: "x", count: 2049)] {
            XCTAssertThrowsError(try DialPlan(text), text)
        }
    }

    func testDisabledPlanAndBounds() throws {
        XCTAssertEqual(try DialPlan(" \n").apply(to: "1234"), "1234")
        XCTAssertThrowsError(try DialPlan("x.").apply(to: String(repeating: "1", count: 129)))
        XCTAssertThrowsError(try DialPlan("x.").apply(to: "123\n"))
        XCTAssertThrowsError(try DialPlan("<0:>").apply(to: "0"))
        XCTAssertThrowsError(try DialPlan(String(repeating: "x.", count: 60) + "9").apply(to: String(repeating: "1", count: 128)))
    }
}
