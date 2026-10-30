import Foundation

/// What the games keep on this device, in UserDefaults as the app's other
/// local settings are (the voice, `mcfly.voice`): 2048's best score and the
/// game in progress, Traffic Jam's and Penguin March's level and each
/// level's best, Scoop Shop's best and who worked last, every Color by
/// Number picture as far as it's painted, the Solitaire game in progress
/// with its wins and fewest moves, and Pairs' fewest turns for each size of
/// board. Tic-tac-toe, Four in a Row and Dots and Boxes keep their score
/// only while open, as on the display.
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

    // MARK: Color by Number

    /// Each picture's progress (`ColorBoard.saved`), by the picture's id.
    public var colorProgress: [String: String] {
        defaults.dictionary(forKey: Self.prefix + "colors.progress") as? [String: String] ?? [:]
    }

    /// Keeps a picture's progress.
    public func saveColors(_ saved: String, for id: String) {
        var all = colorProgress
        guard all[id] != saved else { return }
        all[id] = saved
        defaults.set(all, forKey: Self.prefix + "colors.progress")
    }

    // MARK: Solitaire

    /// The game in progress, if it holds every card once; nil once one is won.
    public var solitaire: Solitaire? {
        get {
            defaults.data(forKey: Self.prefix + "solitaire.game")
                .flatMap { try? JSONDecoder().decode(Solitaire.self, from: $0) }
                .flatMap { $0.isValid && !$0.won ? $0 : nil }
        }
        set {
            if let newValue, !newValue.won, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Self.prefix + "solitaire.game")
            } else {
                defaults.removeObject(forKey: Self.prefix + "solitaire.game")
            }
        }
    }

    public var solitaireWins: Int { int("solitaire.wins") }
    /// The fewest moves in a win; 0 before the first.
    public var solitaireFewest: Int { int("solitaire.fewest") }

    /// A win in `moves`: one more, and the fewest if it is.
    public func recordSolitaireWin(moves: Int) {
        setInt(solitaireWins + 1, "solitaire.wins")
        if solitaireFewest == 0 || moves < solitaireFewest { setInt(moves, "solitaire.fewest") }
    }

    // MARK: Pairs

    /// The fewest turns to clear each size of board alone.
    public var pairsBest: [Int: Int] { table("pairs.best") }

    /// Keeps `moves` for a board of `size` cards if it's the fewest yet.
    public func recordPairs(size: Int, moves: Int) {
        var best = pairsBest
        if let old = best[size], old <= moves { return }
        best[size] = moves
        setTable(best, "pairs.best")
    }
}
