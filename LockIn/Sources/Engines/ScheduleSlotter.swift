import Foundation

/// Finds a start time of `duration` inside a window that does not overlap
/// occupied blocks. Prefers the requested time; if that collides, slides to
/// just after the conflict, then just before, then the nearest gap.
enum ScheduleSlotter {
    struct Interval: Equatable {
        var start: Date
        var end: Date

        var duration: TimeInterval { end.timeIntervalSince(start) }

        func overlaps(_ other: Interval) -> Bool {
            start < other.end && end > other.start
        }

        func contains(_ date: Date) -> Bool {
            date >= start && date < end
        }
    }

    static func firstFit(duration: TimeInterval, preferred: Date, window: Interval, occupied: [Interval]) -> Date {
        guard duration > 0, window.duration >= duration else { return clamp(preferred, to: window, duration: duration) }

        let merged = merge(occupied.filter { $0.overlaps(window) })
        let candidate = clamp(preferred, to: window, duration: duration)
        let proposed = Interval(start: candidate, end: candidate.addingTimeInterval(duration))
        if !merged.contains(where: { $0.overlaps(proposed) }) {
            return candidate
        }

        let gaps = gaps(in: window, occupied: merged).filter { $0.duration >= duration }
        guard !gaps.isEmpty else { return candidate }

        // Just after the block that ate the preferred time, if that gap fits.
        if let colliding = merged.first(where: { $0.overlaps(proposed) }) {
            let after = colliding.end
            let afterEnd = after.addingTimeInterval(duration)
            if after >= window.start, afterEnd <= window.end,
               !merged.contains(where: { $0.overlaps(Interval(start: after, end: afterEnd)) }) {
                return after
            }
            let before = colliding.start.addingTimeInterval(-duration)
            if before >= window.start,
               !merged.contains(where: { $0.overlaps(Interval(start: before, end: colliding.start)) }) {
                return before
            }
        }

        return gaps.min { a, b in
            abs(a.start.timeIntervalSince(preferred)) < abs(b.start.timeIntervalSince(preferred))
        }?.start ?? candidate
    }

    static func merge(_ intervals: [Interval]) -> [Interval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [Interval] = []
        for interval in sorted {
            guard let last = merged.last else {
                merged.append(interval)
                continue
            }
            if interval.start <= last.end {
                merged[merged.count - 1].end = max(last.end, interval.end)
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    static func gaps(in window: Interval, occupied: [Interval]) -> [Interval] {
        var cursor = window.start
        var result: [Interval] = []
        for block in merge(occupied) {
            if block.start > cursor {
                result.append(Interval(start: cursor, end: min(block.start, window.end)))
            }
            cursor = max(cursor, block.end)
            if cursor >= window.end { break }
        }
        if cursor < window.end {
            result.append(Interval(start: cursor, end: window.end))
        }
        return result
    }

    private static func clamp(_ preferred: Date, to window: Interval, duration: TimeInterval) -> Date {
        let latest = window.end.addingTimeInterval(-duration)
        if preferred < window.start { return window.start }
        if preferred > latest { return max(window.start, latest) }
        return preferred
    }
}
