import Foundation

// A project's stages as the console draws them (stageTrack() and
// timeInStage() in admin/lib/feed-layout.ts, FeedStore::stageTrack on the
// display), so all three tell a project's stages the same way.

public struct StageTrack: Hashable, Sendable {
    public enum State: String, Hashable, Sendable {
        case done, current, blocked, paused, next
    }

    public struct Step: Hashable, Sendable {
        public let name: String
        public let state: State
        /// Its place, from 1.
        public let number: Int

        /// The word under it on the stepper: "Done", "Now", "Blocked here",
        /// "Paused here", or "Stage 3" for one not reached.
        public var word: String {
            switch state {
            case .done: return "Done"
            case .current: return "Now"
            case .blocked: return "Blocked here"
            case .paused: return "Paused here"
            case .next: return "Stage \(number)"
            }
        }
    }

    public let steps: [Step]
    /// The stage it is in; nil before the first and once done.
    public let current: String?
    /// Its place (from 0): -1 before the first, the count once done.
    public let index: Int
    /// "Build", "Blocked in App Review", "All 4 stages done", "Not started".
    public let headline: String
    /// "2 of 4", or "4 stages" before the first.
    public let position: String

    /// The step it is in, if it is in one.
    public var here: Step? { steps.indices.contains(index) ? steps[index] : nil }

    /// The stages as steps: the ones before its stage done, its stage in the
    /// project's status (blocked or paused, else current), the rest next. A
    /// done project has been through them all, a planned one has started
    /// none. Nil without stages. The stage is matched exactly, as the
    /// console's indexOf.
    public init?(stages: [String], stage: String?, status: Project.Status) {
        let n = stages.count
        guard n > 0 else { return nil }
        func steps(_ state: (Int) -> State) -> [Step] {
            stages.enumerated().map { Step(name: $1, state: state($0), number: $0 + 1) }
        }
        if status == .done {
            self.steps = steps { _ in .done }
            current = nil
            index = n
            headline = n == 1 ? "Done" : "All \(n) stages done"
            position = "\(n) of \(n)"
            return
        }
        // Planned: lined up, none started, whatever stage it names.
        if status == .planned {
            self.steps = steps { _ in .next }
            current = nil
            index = -1
            headline = "Planned"
            position = n == 1 ? "1 stage" : "\(n) stages"
            return
        }
        let index = stage.flatMap { stages.firstIndex(of: $0) } ?? -1
        let here: State = status == .blocked ? .blocked : status == .paused ? .paused : .current
        self.steps = steps { $0 < index ? .done : $0 == index ? here : .next }
        self.index = index
        guard index >= 0 else {
            current = nil
            headline = "Not started"
            position = n == 1 ? "1 stage" : "\(n) stages"
            return
        }
        let name = stages[index]
        current = name
        headline = here == .blocked ? "Blocked in \(name)" : here == .paused ? "Paused in \(name)" : name
        position = "\(index + 1) of \(n)"
    }

    /// How long a project has been in its stage: "under an hour", "5 hr",
    /// "3 days", "2 wk", "4 mo". Empty without a time.
    public static func timeInStage(since: Date?, now: Date) -> String {
        guard let since else { return "" }
        let hours = max(0, now.timeIntervalSince(since)) / 3600
        if hours < 1 { return "under an hour" }
        if hours < 24 { return "\(Int(hours)) hr" }
        let days = Int(hours / 24)
        if days < 14 { return days == 1 ? "1 day" : "\(days) days" }
        if days < 60 { return "\(days / 7) wk" }
        return "\(days / 30) mo"
    }
}

extension Project {
    /// Its stages as steps, when the agent lays them out.
    public var stageTrack: StageTrack? { StageTrack(stages: stages, stage: stage, status: status) }

    /// How long it has been in the stage it is in ("3 days"); empty before
    /// the first stage, once it's done, or without stages.
    public func timeInStage(now: Date = .now) -> String {
        guard stageTrack?.current != nil else { return "" }
        return StageTrack.timeInStage(since: stageSince, now: now)
    }
}
