import Testing

struct CSVTests {
    @Test func quotedFieldKeepsCommas() {
        let text = "video,light,notes\nclip_1,indoor,\"black mat, white ball (30 cm)\"\n"
        #expect(
            CSV.records(text) == [["video": "clip_1", "light": "indoor", "notes": "black mat, white ball (30 cm)"]])
    }

    @Test func doubledQuoteIsEscape() {
        #expect(CSV.parse("a,\"say \"\"hi\"\"\"\n") == [["a", "say \"hi\""]])
    }

    @Test func crlfAndMissingTrailingNewline() {
        #expect(CSV.parse("a,b\r\n1,2") == [["a", "b"], ["1", "2"]])
    }

    @Test func emptyTrailingFieldAndBlankLines() {
        let text = "frame,seconds,notes\n1,0.5,\n\n"
        #expect(CSV.records(text) == [["frame": "1", "seconds": "0.5", "notes": ""]])
    }

    @Test func shortRowFillsMissingKeysWithEmpty() {
        #expect(CSV.records("a,b,c\n1,2\n") == [["a": "1", "b": "2", "c": ""]])
    }
}
