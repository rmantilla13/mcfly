import Foundation

/// What a market agent adds to a quote, `quotes.data` (docs/AGENTS.md,
/// "Holdings, signals and the day's numbers"): the holding, signals and the
/// day's numbers. Numbers may come as JSON numbers or strings ("1,234.50");
/// anything else is left out rather than failing the whole feed.
public struct QuoteData: Codable, Hashable, Sendable {
    public var position: Position?
    public var signals: [Signal]
    public var stats: Stats?

    public init(position: Position? = nil, signals: [Signal] = [], stats: Stats? = nil) {
        self.position = position; self.signals = signals; self.stats = stats
    }

    public struct Position: Codable, Hashable, Sendable {
        public var shares, avgCost, value, dayChange, totalChange, totalChangePct, weightPct: Double?

        public init(shares: Double? = nil, avgCost: Double? = nil, value: Double? = nil, dayChange: Double? = nil,
                    totalChange: Double? = nil, totalChangePct: Double? = nil, weightPct: Double? = nil) {
            self.shares = shares; self.avgCost = avgCost; self.value = value; self.dayChange = dayChange
            self.totalChange = totalChange; self.totalChangePct = totalChangePct; self.weightPct = weightPct
        }

        enum CodingKeys: String, CodingKey {
            case shares, value
            case avgCost = "avg_cost"
            case dayChange = "day_change"
            case totalChange = "total_change"
            case totalChangePct = "total_change_pct"
            case weightPct = "weight_pct"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            shares = c.number(.shares); avgCost = c.number(.avgCost); value = c.number(.value)
            dayChange = c.number(.dayChange); totalChange = c.number(.totalChange)
            totalChangePct = c.number(.totalChangePct); weightPct = c.number(.weightPct)
        }
    }

    public struct Signal: Codable, Hashable, Sendable {
        public enum Tone: String, Codable, Sendable { case up, down, watch }
        public var text: String
        public var tone: Tone

        public init(text: String, tone: Tone = .watch) { self.text = text; self.tone = tone }

        enum CodingKeys: String, CodingKey { case text, tone }

        /// `{ "text", "tone" }`, or a plain string (tone watch). An unknown tone is watch.
        public init(from decoder: Decoder) throws {
            if let text = try? decoder.singleValueContainer().decode(String.self) {
                self.init(text: text)
                return
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let tone = (try? c.decodeIfPresent(String.self, forKey: .tone)).flatMap { $0 }.flatMap(Tone.init(rawValue:))
            self.init(text: (try? c.decodeIfPresent(String.self, forKey: .text)).flatMap { $0 } ?? "", tone: tone ?? .watch)
        }
    }

    public struct Stats: Codable, Hashable, Sendable {
        public var open, high, low, prevClose, volume, avgVolume, marketCap, pe, low52w, high52w, dividendYield: Double?
        public var earnings: String?

        public init(open: Double? = nil, high: Double? = nil, low: Double? = nil, prevClose: Double? = nil,
                    volume: Double? = nil, avgVolume: Double? = nil, marketCap: Double? = nil, pe: Double? = nil,
                    low52w: Double? = nil, high52w: Double? = nil, dividendYield: Double? = nil, earnings: String? = nil) {
            self.open = open; self.high = high; self.low = low; self.prevClose = prevClose; self.volume = volume
            self.avgVolume = avgVolume; self.marketCap = marketCap; self.pe = pe; self.low52w = low52w
            self.high52w = high52w; self.dividendYield = dividendYield; self.earnings = earnings
        }

        enum CodingKeys: String, CodingKey {
            case open, high, low, volume, pe, earnings
            case prevClose = "prev_close"
            case avgVolume = "avg_volume"
            case marketCap = "market_cap"
            case low52w = "low_52w"
            case high52w = "high_52w"
            case dividendYield = "dividend_yield"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            open = c.number(.open); high = c.number(.high); low = c.number(.low); prevClose = c.number(.prevClose)
            volume = c.number(.volume); avgVolume = c.number(.avgVolume); marketCap = c.number(.marketCap)
            pe = c.number(.pe); low52w = c.number(.low52w); high52w = c.number(.high52w)
            dividendYield = c.number(.dividendYield)
            earnings = (try? c.decodeIfPresent(String.self, forKey: .earnings)).flatMap { $0 }
        }
    }

    enum CodingKeys: String, CodingKey { case position, signals, stats }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        position = (try? c.decodeIfPresent(Position.self, forKey: .position)).flatMap { $0 }
        signals = (try? c.decodeIfPresent([Signal].self, forKey: .signals)).flatMap { $0 } ?? []
        stats = (try? c.decodeIfPresent(Stats.self, forKey: .stats)).flatMap { $0 }
    }
}

/// The newest row's `data` per symbol (the `quotes_latest` view), so the
/// history doesn't carry it 2000 times.
public struct QuoteLatest: Codable, Hashable, Sendable {
    public var symbol: String
    public var asOf: Date
    public var data: QuoteData?

    public init(symbol: String, asOf: Date, data: QuoteData?) { self.symbol = symbol; self.asOf = asOf; self.data = data }

    enum CodingKeys: String, CodingKey {
        case symbol, data
        case asOf = "as_of"
    }
}

/// A holding as shown: what the agent sent, with what it left out worked out
/// (value from shares × price, the gain from the average cost, today's move
/// from shares × change), as the display does (FeedStore.cpp, positionOf).
public struct Holding: Hashable, Sendable {
    public var shares: Double?
    public var value: Double
    public var avgCost: Double?
    public var dayChange: Double?
    public var totalChange: Double?
    public var totalChangePct: Double?
    /// Its share of every holding shown, in percent.
    public var weightPct: Double?
}

public struct PriceRange: Hashable, Sendable, Identifiable {
    public var id: String { label }
    public var label: String
    public var low: Double
    public var high: Double
    /// Where the price sits: 0 at the low, 1 at the high.
    public var position: Double
}

public struct MarketStat: Hashable, Sendable, Identifiable {
    public var id: String { label }
    public var label: String
    public var value: String
}

/// What the Markets detail shows under the price.
public struct QuoteInsight: Hashable, Sendable {
    public var holding: Holding?
    public var signals: [QuoteData.Signal]
    public var stats: [MarketStat]
    public var ranges: [PriceRange]

    public static let empty = QuoteInsight(holding: nil, signals: [], stats: [], ranges: [])
    public var isEmpty: Bool { holding == nil && signals.isEmpty && stats.isEmpty && ranges.isEmpty }
}

/// The holdings among the shown symbols, summed. The percentages are on what
/// each move is measured against: the value before today's move, the cost.
public struct Portfolio: Hashable, Sendable {
    public var count: Int
    public var value: Double
    public var dayChange: Double?
    public var dayChangePct: Double?
    public var totalChange: Double?
    public var totalChangePct: Double?

    public static let none = Portfolio(count: 0, value: 0)
    public var isEmpty: Bool { count == 0 }
}

/// A holding and its signals count while their row is part of the agent's
/// newest push: the rows one push writes share their `created_at`. A position
/// the agent stopped sending (sold) goes; its price stays.
public enum Holdings {
    public static let maxSignals = 6

    public static func build(series: [QuoteSeries], latest: [QuoteLatest]) -> (insights: [String: QuoteInsight], portfolio: Portfolio) {
        var lastPush: [UUID: Date] = [:]
        for row in series.flatMap(\.history) {
            lastPush[row.agentId] = max(lastPush[row.agentId] ?? row.createdAt, row.createdAt)
        }
        let latestBySymbol = Dictionary(latest.map { ($0.symbol, $0) }, uniquingKeysWith: { a, _ in a })

        var insights: [String: QuoteInsight] = [:]
        for s in series {
            let q = s.latest
            let data = latestBySymbol[s.symbol].flatMap { $0.asOf == q.asOf ? $0.data : nil } ?? q.data
            guard let data else { continue }
            let current = lastPush[q.agentId] == q.createdAt
            let change = s.change
            let insight = QuoteInsight(
                holding: current ? holding(data.position, price: q.price, change: change) : nil,
                signals: current ? Array(data.signals.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(maxSignals)) : [],
                stats: stats(data.stats, currency: q.currency),
                ranges: ranges(data.stats, price: q.price))
            if !insight.isEmpty { insights[s.symbol] = insight }
        }

        // Each holding's share of the total (unless the agent said), and the sums.
        let held = insights.filter { $0.value.holding != nil }
        let total = held.values.reduce(0) { $0 + ($1.holding?.value ?? 0) }
        var portfolio = Portfolio(count: held.count, value: total)
        var day = 0.0, dayBase = 0.0, gain = 0.0, cost = 0.0, anyDay = false, anyGain = false
        for (symbol, insight) in held {
            guard var h = insight.holding else { continue }
            if h.weightPct == nil, total > 0 { h.weightPct = h.value / total * 100 }
            insights[symbol]?.holding = h
            if let d = h.dayChange { day += d; dayBase += h.value - d; anyDay = true }
            if let g = h.totalChange { gain += g; cost += h.value - g; anyGain = true }
        }
        if anyDay {
            portfolio.dayChange = day
            portfolio.dayChangePct = dayBase > 0 ? day / dayBase * 100 : nil
        }
        if anyGain {
            portfolio.totalChange = gain
            portfolio.totalChangePct = cost > 0 ? gain / cost * 100 : nil
        }
        return (insights, portfolio)
    }

    static func holding(_ p: QuoteData.Position?, price: Double, change: Double?) -> Holding? {
        guard let p else { return nil }
        guard let value = p.value ?? p.shares.map({ $0 * price }), value != 0 || (p.shares ?? 0) != 0 else { return nil }
        var total = p.totalChange
        if total == nil, let avg = p.avgCost, let shares = p.shares { total = value - avg * shares }
        var totalPct = p.totalChangePct
        if totalPct == nil, let total, value - total > 0 { totalPct = total / (value - total) * 100 }
        var day = p.dayChange
        if day == nil, let shares = p.shares, let change { day = shares * change }
        return Holding(shares: p.shares, value: value, avgCost: p.avgCost, dayChange: day, totalChange: total,
                       totalChangePct: totalPct, weightPct: p.weightPct)
    }

    static func ranges(_ s: QuoteData.Stats?, price: Double) -> [PriceRange] {
        guard let s else { return [] }
        return [("Today", s.low, s.high), ("52 weeks", s.low52w, s.high52w)].compactMap { label, low, high in
            guard let low, let high, high >= low else { return nil }
            let position = high > low ? min(max((price - low) / (high - low), 0), 1) : 0.5
            return PriceRange(label: label, low: low, high: high, position: position)
        }
    }

    /// In the display's order, only what was sent (the ranges are `ranges`).
    static func stats(_ s: QuoteData.Stats?, currency: String) -> [MarketStat] {
        guard let s else { return [] }
        var out: [MarketStat] = []
        func add(_ label: String, _ value: String?) { if let value, !value.isEmpty { out.append(MarketStat(label: label, value: value)) } }
        add("Open", s.open.map { Format.price($0, currency: currency) })
        add("Prev close", s.prevClose.map { Format.price($0, currency: currency) })
        if let volume = s.volume {
            var label = Format.compact(volume)
            if let avg = s.avgVolume, avg > 0 { label += " · " + (volume / avg).formatted(.number.precision(.fractionLength(1))) + "× avg" }
            add("Volume", label)
        }
        add("Market cap", s.marketCap.map { (currency == "USD" ? "$" : "") + Format.compact($0) })
        add("P/E", s.pe.map { $0.formatted(.number.precision(.fractionLength(1))) })
        add("Dividend", s.dividendYield.map { $0.formatted(.number.precision(.fractionLength(2))) + "%" })
        add("Earnings", s.earnings.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)) })
        return out
    }
}

extension QuoteSeries {
    /// The move since the last close: the agent's change, else the step from
    /// the price before (the display's rule).
    public var change: Double? {
        latest.change ?? (history.count > 1 ? latest.price - history[1].price : nil)
    }
}

extension Format {
    /// Volumes and market caps: 48.2M, 3.7T.
    public static func compact(_ value: Double) -> String {
        for (size, suffix) in [(1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")] where abs(value) >= size {
            let n = value / size
            return n.formatted(.number.precision(.fractionLength(abs(n) >= 100 ? 0 : 1))) + suffix
        }
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    /// "+$1,234.50" / "−$48.00".
    public static func signedPrice(_ value: Double, currency: String = "USD") -> String {
        (value < 0 ? "−" : "+") + price(abs(value), currency: currency)
    }

    /// Whole shares plainly, a fraction to four places: "40 shares", "0.1864 shares", "1 share".
    public static func shares(_ value: Double) -> String {
        if value == 1 { return "1 share" }
        let whole = abs(value - value.rounded()) < 1e-9
        return value.formatted(.number.precision(.fractionLength(whole ? 0...0 : 0...4))) + " shares"
    }
}

extension KeyedDecodingContainer {
    /// A JSON number or a numeric string ("$1,234.50", "12%"); nil for anything else.
    func number(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d.isFinite ? d : nil }
        guard let s = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        let cleaned = s.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        guard let d = Double(cleaned), d.isFinite else { return nil }
        return d
    }
}
