import AppKit
import UseCases
import XCTest

final class BrazilianNumberFormattingTests: XCTestCase {
    func testFormatsBrazilianNumbersWithoutChangingDialableValue() {
        let formatter = AKTelephoneNumberFormatter()
        let cases = [
            "33334444": "3333-4444",
            "999998888": "99999-8888",
            "1133334444": "(11) 3333-4444",
            "11999998888": "(11) 99999-8888",
            "42991648352": "(42) 99164-8352",
            "+5511999998888": "+55 (11) 99999-8888",
            "+551133334444": "+55 (11) 3333-4444",
            "5511999998888": "55 (11) 99999-8888",
            "08001234567": "0800 123 4567",
            "03003376786": "0300 337 6786",
            "+12125551234": "+1 (212) 555-1234"
        ]
        for (number, expected) in cases {
            let display = formatter.string(for: number)!
            XCTAssertEqual(display, expected, number)
            XCTAssertEqual(formatter.telephoneNumber(from: display), number)
            XCTAssertEqual(formatter.string(for: display), display)
        }
    }

    func testPreservesExtensionsServiceCodesAndUnknownFormats() {
        let formatter = AKTelephoneNumberFormatter()
        for number in ["", "118", "103", "190", "123456", "1234567", "*8", "*21*118#", "#31#11999998888",
                       "sip:118@example.com", "118@example.com", "+442079460123", "011999998888",
                       "0011999998888", "12345678", "9999999999999999", "33334444\n"] {
            XCTAssertEqual(formatter.string(for: number), number)
        }
        XCTAssertNil(formatter.string(for: 123))
    }

    func testHistoryFormattingIsOptionalAndPreservesRawAddressAndName() {
        let contact = MatchedContact(name: "", address: .phone(number: "11999998888", label: "mobile"))
        let formatted = PresentationContact(contact: contact, color: .labelColor, formatsPhoneNumbers: true)
        let raw = PresentationContact(contact: contact, color: .labelColor, formatsPhoneNumbers: false)
        XCTAssertEqual(formatted.title, "(11) 99999-8888")
        XCTAssertEqual(formatted.address, "11999998888")
        XCTAssertEqual(raw.title, "11999998888")
        let named = MatchedContact(name: "Maria", address: contact.address)
        let presentation = PresentationContact(contact: named, color: .labelColor, formatsPhoneNumbers: true)
        XCTAssertEqual(presentation.title, "Maria")
        XCTAssertEqual(presentation.tooltip, "(11) 99999-8888")
        XCTAssertEqual(presentation.address, "11999998888")
    }

    func testHistoryDoesNotFormatSIPAddresses() {
        let contact = MatchedContact(name: "", address: .email(address: "11999998888@example.com", label: "SIP"))
        let presentation = PresentationContact(contact: contact, color: .labelColor, formatsPhoneNumbers: true)
        XCTAssertEqual(presentation.title, "11999998888@example.com")
    }

    func testHistoryHonorsSplitPreferenceWithoutChangingStoredNumber() {
        for (number, split, unsplit) in [("+12125551234", "+1 (212) 555-12-34", "+1 (212) 555-1234"),
                                         ("+74951234567", "+7 (495) 123-45-67", "+7 (495) 123-4567")] {
            for name in ["", "Maria"] {
                let contact = MatchedContact(name: name, address: .phone(number: number, label: "mobile"))
                for (format, splits, expected) in [(true, true, split), (true, false, unsplit), (false, true, number)] {
                    let presentation = PresentationContact(contact: contact, color: .labelColor,
                                                           formatsPhoneNumbers: format, splitsLastFourDigits: splits)
                    XCTAssertEqual(name.isEmpty ? presentation.title : presentation.tooltip, expected)
                    XCTAssertEqual(presentation.address, number)
                    if !name.isEmpty { XCTAssertEqual(presentation.title, name) }
                }
            }
        }
    }
}
