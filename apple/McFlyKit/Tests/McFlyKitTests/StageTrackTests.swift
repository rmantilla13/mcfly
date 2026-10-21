import XCTest
@testable import McFlyKit

/// The console's cases (admin/tests/feed-layout.test.mjs), so the app, the
/// display and the console tell a project's stages the same way.
final class StageTrackTests: XCTestCase {
    private let stages = ["Plan", "Build", "Review", "Ship"]

    private func states(_ track: StageTrack?) -> [StageTrack.State] { track?.steps.map(\.state) ?? [] }

    func testStepsFollowTheProjectsStatus() throws {
        let active = try XCTUnwrap(StageTrack(stages: stages, stage: "Build", status: .active))
        XCTAssertEqual(states(active), [.done, .current, .next, .next])
        XCTAssertEqual(active.current, "Build")
        XCTAssertEqual(active.index, 1)
        XCTAssertEqual(active.headline, "Build")
        XCTAssertEqual(active.position, "2 of 4")
        XCTAssertEqual(active.here?.word, "Now")
        // Blocked or paused, the stage it's in says so.
        let blocked = try XCTUnwrap(StageTrack(stages: stages, stage: "Review", status: .blocked))
        XCTAssertEqual(states(blocked), [.done, .done, .blocked, .next])
        XCTAssertEqual(blocked.headline, "Blocked in Review")
        XCTAssertEqual(blocked.steps.map(\.word), ["Done", "Done", "Blocked here", "Stage 4"])
        let paused = try XCTUnwrap(StageTrack(stages: stages, stage: "Ship", status: .paused))
        XCTAssertEqual(paused.headline, "Paused in Ship")
        XCTAssertEqual(states(paused), [.done, .done, .done, .paused])
        XCTAssertEqual(paused.here?.word, "Paused here")
    }

    func testADoneProjectHasBeenThroughThemAll() throws {
        // Whatever stage it last named.
        let done = try XCTUnwrap(StageTrack(stages: stages, stage: "Build", status: .done))
        XCTAssertEqual(states(done), [.done, .done, .done, .done])
        XCTAssertNil(done.current)
        XCTAssertNil(done.here)
        XCTAssertEqual(done.index, 4)
        XCTAssertEqual(done.headline, "All 4 stages done")
        XCTAssertEqual(done.position, "4 of 4")
        XCTAssertEqual(StageTrack(stages: ["Ship"], stage: nil, status: .done)?.headline, "Done")
    }

    func testBeforeTheFirstStage() throws {
        let fresh = try XCTUnwrap(StageTrack(stages: stages, stage: nil, status: .active))
        XCTAssertEqual(states(fresh), [.next, .next, .next, .next])
        XCTAssertEqual(fresh.index, -1)
        XCTAssertEqual(fresh.headline, "Not started")
        XCTAssertEqual(fresh.position, "4 stages")
        XCTAssertEqual(StageTrack(stages: ["Ship"], stage: nil, status: .active)?.position, "1 stage")
        // A stage the stages don't name, exactly (the console's indexOf), is none.
        XCTAssertEqual(StageTrack(stages: stages, stage: "build", status: .active)?.headline, "Not started")
        // No stages, no track.
        XCTAssertNil(StageTrack(stages: [], stage: nil, status: .active))
    }

    func testTimeInStage() {
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        func ago(_ hours: Double) -> String { StageTrack.timeInStage(since: now.addingTimeInterval(-hours * 3600), now: now) }
        XCTAssertEqual(ago(20.0 / 60), "under an hour")
        XCTAssertEqual(ago(59.0 / 60), "under an hour")
        XCTAssertEqual(ago(1), "1 hr")
        XCTAssertEqual(ago(5 + 10.0 / 60), "5 hr")
        XCTAssertEqual(ago(23.9), "23 hr")
        XCTAssertEqual(ago(24), "1 day")
        XCTAssertEqual(ago(30), "1 day")
        XCTAssertEqual(ago(3 * 24), "3 days")
        XCTAssertEqual(ago(14 * 24 - 1), "13 days")
        XCTAssertEqual(ago(14 * 24), "2 wk")
        XCTAssertEqual(ago(20 * 24), "2 wk")
        XCTAssertEqual(ago(60 * 24 - 1), "8 wk")
        XCTAssertEqual(ago(60 * 24), "2 mo")
        XCTAssertEqual(ago(130 * 24), "4 mo")
        XCTAssertEqual(ago(-1), "under an hour") // a clock a little ahead
        XCTAssertEqual(StageTrack.timeInStage(since: nil, now: now), "")
    }

    func testAProjectsOwnTrackAndTime() throws {
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        var project = Project(id: UUID(), agentId: UUID(), key: "x", name: "X", status: .blocked, createdAt: now, updatedAt: now,
                              stages: ["Plan", "App Review"], stage: "App Review", stageSince: now.addingTimeInterval(-5 * 86400))
        XCTAssertEqual(project.stageTrack?.headline, "Blocked in App Review")
        XCTAssertEqual(project.timeInStage(now: now), "5 days")
        // Done, it's in no stage, so no time either.
        project.status = .done
        XCTAssertEqual(project.timeInStage(now: now), "")
        project.stages = []
        XCTAssertNil(project.stageTrack)
    }
}
