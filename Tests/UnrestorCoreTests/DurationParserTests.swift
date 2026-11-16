import Testing
@testable import UnrestorCore

@Test func parsesUnits() {
    #expect(DurationParser.parse("90m") == 5_400)
    #expect(DurationParser.parse("2h") == 7_200)
    #expect(DurationParser.parse("1h30m") == 5_400)
    #expect(DurationParser.parse("45s") == 45)
    #expect(DurationParser.parse("1d") == 86_400)
    #expect(DurationParser.parse("15") == 900)
    #expect(DurationParser.parse(" 2H ") == 7_200)
}

@Test func rejectsNonsense() {
    for bad in ["", "0", "0m", "-5", "h", "1x", "1h1h", "m30", "1.5h", "30m5"] {
        #expect(DurationParser.parse(bad) == nil, "\(bad)")
    }
}

@Test func formatsDurations() {
    #expect(DurationParser.format(5_400) == "1h 30m")
    #expect(DurationParser.format(7_200) == "2h")
    #expect(DurationParser.format(300) == "5m")
    #expect(DurationParser.format(20) == "20s")
}
