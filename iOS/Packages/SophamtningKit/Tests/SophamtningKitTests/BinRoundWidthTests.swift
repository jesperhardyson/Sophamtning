import CoreGraphics
import SophamtningDesign
import Testing

/// Kärlet i tomt läge växer med textstorleken, men högst till 200 pt, så att sökfältet inte trycks långt ned.
@Suite struct BinRoundWidthTests {
    @Test func normalStorlekArOforandrad() {
        #expect(BinRoundView.drawnWidth(scaled: 135) == 135)
    }

    @Test func storstaTextenStannarVid200() {
        #expect(BinRoundView.maxWidth == 200)
        #expect(BinRoundView.drawnWidth(scaled: 200) == 200)
        #expect(BinRoundView.drawnWidth(scaled: 320) == 200)
    }
}
