import Testing
@testable import ChillMac

@Suite("CoolStatusMenuBuilder", .tags(.unit, .fan))
struct CoolStatusMenuBuilderTests {
    @Test(arguments: [
        (CoolIntent.native, CoolStatusMenuBuilder.ItemTag.modeNative.rawValue),
        (CoolIntent.balanced, CoolStatusMenuBuilder.ItemTag.modeBalanced.rawValue),
        (CoolIntent.performance, CoolStatusMenuBuilder.ItemTag.modePerformance.rawValue),
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
