import Testing
@testable import ChillMac

@Suite("CoolStatusMenuBuilder", .tags(.unit, .fan))
struct CoolStatusMenuBuilderTests {
    @Test(arguments: [
        (CoolIntent.native, CoolStatusMenuBuilder.ItemTag.modeNative.rawValue),
        (CoolIntent.max, CoolStatusMenuBuilder.ItemTag.modeMax.rawValue),
        (CoolIntent.ultra, CoolStatusMenuBuilder.ItemTag.modeUltra.rawValue),
    ])
    func tagRoundTrip(intent: CoolIntent, expectedTag: Int) {
        #expect(CoolStatusMenuBuilder.tag(for: intent) == expectedTag)
        #expect(CoolStatusMenuBuilder.intent(forTag: expectedTag) == intent)
    }

    @Test("unknown tags map to nil")
    func unknownTag() {
        #expect(CoolStatusMenuBuilder.intent(forTag: 0) == nil)
        #expect(CoolStatusMenuBuilder.intent(forTag: 999) == nil)
    }
}
