import Testing
@testable import ChillMac

@Suite("FanTargetCommit", .tags(.unit, .fan))
struct FanTargetCommitTests {
    @Test("successful reply caches manual target")
    func successCachesOverrides() {
        var manual: [Int: Bool] = [:]
        var targets: [Int: Double] = [:]
        var lastSent: [Int: Double] = [:]

        FanTargetCommit.apply(
            ok: true,
            fanId: 0,
            rpm: 5300,
            manualOverrides: &manual,
            targetOverrides: &targets,
            lastSentRPM: &lastSent
        )

        #expect(manual[0] == true)
        #expect(targets[0] == 5300)
        #expect(lastSent[0] == 5300)
    }

    @Test("failed reply clears fake target so next poll can retry")
    func failureClearsOverrides() {
        var manual: [Int: Bool] = [0: true]
        var targets: [Int: Double] = [0: 5300]
        var lastSent: [Int: Double] = [0: 5300]

        FanTargetCommit.apply(
            ok: false,
            fanId: 0,
            rpm: 5300,
            manualOverrides: &manual,
            targetOverrides: &targets,
            lastSentRPM: &lastSent
        )

        #expect(manual[0] == false)
        #expect(targets[0] == nil)
        #expect(lastSent[0] == nil)
    }

    @Test("identical successful reply does not rewrite caches")
    func successIsIdempotent() {
        var manual: [Int: Bool] = [0: true]
        var targets: [Int: Double] = [0: 5300]
        var lastSent: [Int: Double] = [0: 5300]

        FanTargetCommit.apply(
            ok: true,
            fanId: 0,
            rpm: 5300,
            manualOverrides: &manual,
            targetOverrides: &targets,
            lastSentRPM: &lastSent
        )

        #expect(manual[0] == true)
        #expect(targets[0] == 5300)
        #expect(lastSent[0] == 5300)
    }
}

@Suite("PerformanceControl", .tags(.unit, .fan))
struct PerformanceControlTests {
    @Test("actively controlling requires preference, helper, and engagement")
    func requiresHelperReady() {
        #expect(PerformanceControl.isActivelyControlling(performanceMode: true, helperReady: true, coolingEngaged: true))
        #expect(!PerformanceControl.isActivelyControlling(performanceMode: true, helperReady: true, coolingEngaged: false))
        #expect(!PerformanceControl.isActivelyControlling(performanceMode: true, helperReady: false))
        #expect(!PerformanceControl.isActivelyControlling(performanceMode: false, helperReady: true))
        #expect(!PerformanceControl.isActivelyControlling(performanceMode: false, helperReady: false))
    }
}

@Suite("HelperReadiness", .tags(.unit, .fan))
struct HelperReadinessTests {
    @Test("only runningCorrectVersion marks helper ready")
    func onlyLiveHelper() {
        #expect(HelperReadiness.isReady(.runningCorrectVersion))
        #expect(!HelperReadiness.isReady(.runningWrongVersion))
        #expect(!HelperReadiness.isReady(.notRunning))
    }
}
