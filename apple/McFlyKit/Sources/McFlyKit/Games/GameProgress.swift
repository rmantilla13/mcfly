import Foundation

/// What the games keep on this device, in UserDefaults as the app's other
/// local settings are (the voice, `mcfly.voice`): 2048's best score and the
/// game in progress, Traffic Jam's and Penguin March's level and each
/// level's best, Scoop Shop's best and who worked last. Tic-tac-toe and Four
/// in a Row keep their score only while open, as on the display.
public final class GameProgress: @unchecked Sendable {
    public static let shared = GameProgress()

    private let defaults: UserDefaults
    private static let prefix = "mcfly.games."

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func int(_ key: String) -> Int { defaults.integer(forKey: Self.prefix + key) }
    private func setInt(_ value: Int, _ key: String) { defaults.set(value, forKey: Self.prefix + key) }

    /// Level index → a number (fewest moves, most saved), kept as a plist dictionary.
    private func table(_ key: String) -> [Int: Int] {
        let raw = defaults.dictionary(forKey: Self.prefix + key) as? [String: Int] ?? [:]
        return Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in Int(k).map { ($0, v) } })
    }

    private func setTable(_ table: [Int: Int], _ key: String) {
        defaults.set(Dictionary(uniqueKeysWithValues: table.map { (String($0.key), $0.value) }), forKey: Self.prefix + key)
    }

    // MARK: 2048

    public var best2048: Int {
        get { int("2048.best") }
        set { setInt(newValue, "2048.best") }
    }

    /// The game in progress; nil once one is over.
    public var game2048: Game2048.State? {
        get {
            defaults.data(forKey: Self.prefix + "2048.game").flatMap { try? JSONDecoder().decode(Game2048.State.self, from: $0) }
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Self.prefix + "2048.game")
            } else {
                defaults.removeObject(forKey: Self.prefix + "2048.game")
            }
        }
    }

    // MARK: Traffic Jam

    public var trafficLevel: Int {
        get { int("traffic.level") }
        set { setInt(newValue, "traffic.level") }
    }

    /// Fewest moves each solved level took.
    public var trafficBest: [Int: Int] { table("traffic.best") }

    /// Keeps `moves` for `level` if it's the fewest yet.
    public func recordTraffic(level: Int, moves: Int) {
        var best = trafficBest
        if let old = best[level], old <= moves { return }
        best[level] = moves
        setTable(best, "traffic.best")
    }

    // MARK: Scoop Shop

    public var scoopBest: Int {
        get { int("scoop.best") }
        set { setInt(newValue, "scoop.best") }
    }

    public var scoopWorker: ScoopKeeper {
        get { defaults.string(forKey: Self.prefix + "scoop.worker").flatMap(ScoopKeeper.init(rawValue:)) ?? .pip }
        set { defaults.set(newValue.rawValue, forKey: Self.prefix + "scoop.worker") }
    }

    // MARK: Penguin March

    public var penguinLevel: Int {
        get { int("penguins.level") }
        set { setInt(newValue, "penguins.level") }
    }

    /// Most penguins saved on each won level.
    public var penguinBest: [Int: Int] { table("penguins.best") }

    /// Keeps `saved` for `level` if it's a win and the most yet.
    public func recordPenguins(level: Int, saved: Int, need: Int) {
        guard saved >= need else { return }
        var best = penguinBest
        if let old = best[level], old >= saved { return }
        best[level] = saved
        setTable(best, "penguins.best")
    }
}
