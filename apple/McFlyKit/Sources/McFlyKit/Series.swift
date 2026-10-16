import Foundation

// Time-series shaping for the charts and the insights: the console's
// admin/lib/series.ts and the display's helpers in FeedStore.cpp (median,
// robustZ, usualSwing, addRange), ported. Series run oldest → newest. Pure,
// so SeriesTests can check them against the console's cases.

/// Which way a value went.
public enum Trend: String, CaseIterable, Hashable, Sendable {
    case up, down, flat

    /// The sign of a move: up above zero, down below it, flat at zero (or with none).
    public init(_ move: Double?) {
        guard let move, move.isFinite else {
            self = .flat
            return
        }
        self = move > 0 ? .up : move < 0 ? .down : .flat
    }
}

/// A series' low and high, and where its last value sits between them.
public struct SeriesRange: Hashable, Sendable {
    public var low: Double
    public var high: Double
    /// The newest value.
    public var last: Double
    /// 0 at the low, 1 at the high; 0.5 when the series never moved.
    public var position: Double

    public init(low: Double, high: Double, last: Double, position: Double) {
        self.low = low; self.high = high; self.last = last; self.position = position
    }
}

public enum Series {
    /// The display's sparkline length (FeedStore.cpp `kSparklinePoints`): a
    /// row's range and its robust z are read over its newest 60 points.
    public static let sparklinePoints = 60
    /// Fewer earlier points than this and a z-score says more about the
    /// sample than about the value.
    public static let minHistory = 8

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    /// How unusual the last value is against the ones before it: a robust
    /// z-score, (last − median) / (1.4826 · MAD), so one old spike doesn't
    /// hide the next. When over half the history is one value (open orders,
    /// uptime) the MAD is 0 and the mean absolute deviation stands in. Nil
    /// with too little history or no spread at all, never infinite or NaN.
    public static func robustZ(_ values: [Double], minHistory: Int = Series.minHistory) -> Double? {
        guard values.count - 1 >= minHistory, values.count >= 2, let last = values.last else { return nil }
        let earlier = Array(values.dropLast())
        guard let mid = median(earlier) else { return nil }
        let deviations = earlier.map { abs($0 - mid) }
        var scale = 1.4826 * (median(deviations) ?? 0)
        if !(scale > 0) {
            scale = 1.2533 * (deviations.reduce(0, +) / Double(deviations.count))
        }
        guard scale > 0 else { return nil }
        let z = (last - mid) / scale
        return z.isFinite ? z : nil
    }

    /// The usual day-to-day move, in percent: the standard deviation of the
    /// daily % changes, leaving out the last one (today's, the move being
    /// judged). Nil with fewer than `minChanges` earlier days or no movement.
    public static func usualSwing(_ closes: [Double], minChanges: Int = 5) -> Double? {
        var changes: [Double] = []
        if closes.count >= 3 {
            for i in 1..<(closes.count - 1) where closes[i - 1] != 0 {
                changes.append((closes[i] - closes[i - 1]) / abs(closes[i - 1]) * 100)
            }
        }
        guard changes.count >= minChanges, changes.count >= 2 else { return nil }
        let mean = changes.reduce(0, +) / Double(changes.count)
        let variance = changes.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(changes.count - 1)
        let sd = variance.squareRoot()
        return sd.isFinite && sd > 0 ? sd : nil
    }

    /// Low, high and where the last value sits between them (the display's `addRange`).
    public static func range(_ values: [Double]) -> SeriesRange? {
        guard let first = values.first, let last = values.last else { return nil }
        var low = first, high = first
        for value in values {
            low = min(low, value)
            high = max(high, value)
        }
        return SeriesRange(low: low, high: high, last: last, position: high > low ? (last - low) / (high - low) : 0.5)
    }

    /// The last value of each day in the calendar's time zone, oldest first:
    /// a quote's daily closes, however often the agent pushes. `points` run
    /// oldest → newest.
    public static func dailyCloses(_ points: [(date: Date, value: Double)], calendar: Calendar = .current) -> [Double] {
        var closes: [Double] = []
        var previous: Date?
        for point in points {
            if let previous, calendar.isDate(point.date, inSameDayAs: previous) {
                closes[closes.count - 1] = point.value
            } else {
                closes.append(point.value)
            }
            previous = point.date
        }
        return closes
    }

    /// At most `n` values with the shape kept: largest-triangle-three-buckets,
    /// which keeps spikes and dips a plain stride would skip. The first and
    /// last values always survive, so the line still ends on the latest one.
    public static func downsample(_ values: [Double], to n: Int) -> [Double] {
        let count = values.count
        if n <= 0 || count == 0 { return [] }
        if n >= count { return values }
        if n == 1 { return [values[count - 1]] }
        if n == 2 { return [values[0], values[count - 1]] }

        var out = [values[0]]
        let every = Double(count - 2) / Double(n - 2)
        var a = 0
        for i in 0..<(n - 2) {
            // The next bucket's average is the third corner of the triangle.
            let nextStart = Int((Double(i + 1) * every).rounded(.down)) + 1
            let nextEnd = min(Int((Double(i + 2) * every).rounded(.down)) + 1, count)
            var avgT = 0.0, avgV = 0.0
            for j in stride(from: nextStart, to: nextEnd, by: 1) {
                avgT += Double(j)
                avgV += values[j]
            }
            let bucket = Double(max(nextEnd - nextStart, 1))
            avgT /= bucket
            avgV /= bucket

            let from = Int((Double(i) * every).rounded(.down)) + 1
            let to = Int((Double(i + 1) * every).rounded(.down)) + 1
            let ta = Double(a), va = values[a]
            var best = from
            var bestArea = -1.0
            for j in stride(from: from, to: to, by: 1) {
                let area = abs((ta - avgT) * (values[j] - va) - (ta - Double(j)) * (avgV - va))
                if area > bestArea {
                    bestArea = area
                    best = j
                }
            }
            out.append(values[best])
            a = best
        }
        out.append(values[count - 1])
        return out
    }
}

// MARK: The feeds' histories

extension QuoteSeries {
    /// The newest `limit` prices, oldest → newest: the display's sparkline,
    /// and what a quote's range is read over. `prices` is the whole history.
    public func sparkline(limit: Int = Series.sparklinePoints) -> [Double] {
        Array(prices.suffix(max(0, limit)))
    }

    /// The low and high of the sparkline's prices, and where the price sits.
    public var historyRange: SeriesRange? { Series.range(sparkline()) }

    /// The last price of each day in the calendar's zone, oldest first, from
    /// the whole history (the display reads every row for these).
    public func dailyCloses(calendar: Calendar = .current) -> [Double] {
        Series.dailyCloses(history.reversed().map { ($0.asOf, $0.price) }, calendar: calendar)
    }

    /// The usual day-to-day move in percent, today's left out.
    public func usualSwing(calendar: Calendar = .current) -> Double? {
        Series.usualSwing(dailyCloses(calendar: calendar))
    }
}

extension MetricSeries {
    /// The newest `limit` values, oldest → newest: the display's sparkline,
    /// and what a metric's range, robust z and usual value are read over.
    /// `values` is the whole history.
    public func sparkline(limit: Int = Series.sparklinePoints) -> [Double] {
        Array(values.suffix(max(0, limit)))
    }

    /// The low and high of the sparkline's values, and where the latest sits.
    public var historyRange: SeriesRange? { Series.range(sparkline()) }
}
