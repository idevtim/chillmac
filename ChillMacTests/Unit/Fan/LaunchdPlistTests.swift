import Foundation
import Testing
@testable import ChillMac

@Suite("LaunchdPlist", .tags(.unit, .fan))
struct LaunchdPlistTests {
    @Test("helper launchd plist uses BundleProgram under HelperTools")
    func bundleProgramPointsAtHelper() throws {
        let plistURL = repoRoot()
            .appendingPathComponent("FanControlHelper/Launchd.plist")
        let data = try Data(contentsOf: plistURL)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        let dict = try #require(object as? [String: Any])

        #expect(dict["Label"] as? String == "com.idevtim.ChillMac.Helper3")
        #expect(
            dict["BundleProgram"] as? String
                == "Contents/Library/HelperTools/com.idevtim.ChillMac.Helper"
        )
        #expect(dict["RunAtLoad"] as? Bool == true)

        let mach = try #require(dict["MachServices"] as? [String: Any])
        #expect(mach["com.idevtim.ChillMac.Helper3"] as? Bool == true)
    }

    private func repoRoot() -> URL {
        // ChillMacTests/Unit/Fan/<file> → repo root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
