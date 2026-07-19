import Foundation
import Testing
@testable import ChillMac

@Suite("LaunchdPlist", .tags(.unit, .fan))
struct LaunchdPlistTests {
    @Test("helper launchd plist uses BundleProgram under LaunchServices")
    func bundleProgramPointsAtHelper() throws {
        let plistURL = repoRoot()
            .appendingPathComponent("FanControlHelper/Launchd.plist")
        let data = try Data(contentsOf: plistURL)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        let dict = try #require(object as? [String: Any])

        #expect(dict["Label"] as? String == "com.idevtim.ChillMac.Helper")
        #expect(
            dict["BundleProgram"] as? String
                == "Contents/Library/LaunchServices/com.idevtim.ChillMac.Helper"
        )

        let mach = try #require(dict["MachServices"] as? [String: Any])
        #expect(mach["com.idevtim.ChillMac.Helper"] as? Bool == true)
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
