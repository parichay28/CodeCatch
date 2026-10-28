import Testing

@testable import CodeCatch

/// `CodeMask` hides the code inside a message and leaves the message readable.
@Suite struct CodeMaskTests {
    @Test func concealsTheCodeAndLeavesTheCopyAroundIt() throws {
        let masked = try #require(
            CodeMask.masked("OTP is 343106 for txn of INR 273.00 at SWIGGY. Do not share.", code: "343106"))
        #expect(masked == "OTP is •••••• for txn of INR 273.00 at SWIGGY. Do not share.")
    }

    @Test func keepsTheSeparatorsInsideTheCode() throws {
        let masked = try #require(CodeMask.masked("Revolut: Your code is 771 204. Never share it", code: "771204"))
        #expect(masked == "Revolut: Your code is ••• •••. Never share it")
    }

    @Test func doesNotConcealDigitsInsideALongerNumber() {
        #expect(CodeMask.masked("Order 99343106 shipped", code: "343106") == nil)
        #expect(CodeMask.masked("Order 3431069 shipped", code: "343106") == nil)
    }

    @Test func returnsNothingWhenTheCodeIsNotInTheMessage() {
        #expect(CodeMask.masked("Confirm your sign-in", code: "343106") == nil)
        #expect(CodeMask.masked("", code: "343106") == nil)
        #expect(CodeMask.masked("nothing to hide", code: "") == nil)
    }

    @Test func theCodeAloneIsTheWholeMessage() throws {
        let masked = try #require(CodeMask.masked("343106", code: "343106"))
        #expect(masked == "••••••")
    }

    @Test func maskingKeepsTheMessageLength() throws {
        let message = "Your Booking.com verification code is 889687"
        let masked = try #require(CodeMask.masked(message, code: "889687"))
        #expect(masked.count == message.count)
    }
}
