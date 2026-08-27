import Foundation

/// A recurring class meeting, held as first-class data on the profile.
///
/// The planner reads the term schedule from here rather than from the iOS
/// Calendar, so class blocks show up regardless of EventKit permission or which
/// device's calendar happens to be populated. EventKit busy blocks still layer
/// on top for one-off commitments.
struct ClassMeeting: Codable, Equatable, Identifiable {
    var id: UUID
    var courseCode: String          // "STAT 5421"
    var title: String               // "Analysis of Categorical Data"
    var location: String            // "Mechanical Engineering 108"
    var weekdays: [Int]             // Calendar weekday ints: 1 = Sun … 7 = Sat
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int

    init(id: UUID = UUID(), courseCode: String, title: String, location: String,
         weekdays: [Int], startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) {
        self.id = id
        self.courseCode = courseCode
        self.title = title
        self.location = location
        self.weekdays = weekdays
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
    }

    var label: String { "\(courseCode) · \(title)" }

    func meets(on date: Date, calendar: Calendar = .current) -> Bool {
        weekdays.contains(calendar.component(.weekday, from: date))
    }

    /// Concrete start/end `Date`s for the class on `date`, or nil if it doesn't
    /// meet that weekday.
    func window(on date: Date, calendar: Calendar = .current) -> (start: Date, end: Date)? {
        guard meets(on: date, calendar: calendar),
              let start = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: date),
              let end = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: date)
        else { return nil }
        return (start, end)
    }
}

struct TermSchedule: Codable, Equatable {
    var meetings: [ClassMeeting]
    var termStart: Date
    var termEnd: Date
    var commuteMinutes: Int          // door to classroom
    var prepMinutes: Int             // getting ready before leaving

    /// Minutes before the first class to fire the "leave by" nudge.
    var leadMinutes: Int { commuteMinutes + prepMinutes }

    func isInTerm(_ date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: termStart)
            && day <= calendar.startOfDay(for: termEnd)
    }

    /// Every class window on `date`, earliest first. Empty outside the term.
    func sessions(on date: Date, calendar: Calendar = .current)
        -> [(meeting: ClassMeeting, start: Date, end: Date)] {
        guard isInTerm(date, calendar: calendar) else { return [] }
        return meetings
            .compactMap { m in m.window(on: date, calendar: calendar).map { (m, $0.start, $0.end) } }
            .sorted { $0.start < $1.start }
    }

    /// Rahil's UMN Fall 2026 schedule. Term end is a placeholder pending the
    /// real last day of instruction.
    static var rahilFall2026: TermSchedule {
        let cal = Calendar.current
        return TermSchedule(
            meetings: [
                ClassMeeting(courseCode: "CSCI 5715", title: "Spatial Data Science",
                             location: "Keller Hall 3-230",
                             weekdays: [3, 5], startHour: 11, startMinute: 15, endHour: 12, endMinute: 30),
                ClassMeeting(courseCode: "STAT 5421", title: "Analysis of Categorical Data",
                             location: "Mechanical Engineering 108",
                             weekdays: [2, 4, 6], startHour: 13, startMinute: 25, endHour: 14, endMinute: 15),
                ClassMeeting(courseCode: "CSCI 5521", title: "Machine Learning Fundamentals",
                             location: "Murphy Hall 130",
                             weekdays: [2, 4], startHour: 14, startMinute: 30, endHour: 15, endMinute: 45)
            ],
            termStart: cal.date(from: DateComponents(year: 2026, month: 9, day: 8))!,
            termEnd: cal.date(from: DateComponents(year: 2026, month: 12, day: 11))!,
            commuteMinutes: 20,
            prepMinutes: 25
        )
    }
}

/// Chronotype and training rhythm. Wake and bedtime come from here and stay
/// put; the day is fitted around them. A mild night-owl by default — later to
/// bed, later up, no early-morning training.
struct RhythmPreference: Codable, Equatable {
    var weekdayWakeHour: Int
    var weekdayWakeMinute: Int
    var weekendWakeHour: Int
    var weekendWakeMinute: Int
    var bedHour: Int                 // clock hour past midnight, e.g. 1 = 1:00 AM
    var bedMinute: Int
    var caffeineCutoffHour: Int      // 17 = 5:00 PM
    var workoutWeekdays: [Int]       // Calendar weekday ints

    func isWeekend(_ date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    /// The fixed wake time for `date` — weekend days get the later slot.
    func wake(on date: Date, calendar: Calendar = .current) -> Date {
        let weekend = isWeekend(date, calendar: calendar)
        return calendar.date(bySettingHour: weekend ? weekendWakeHour : weekdayWakeHour,
                             minute: weekend ? weekendWakeMinute : weekdayWakeMinute,
                             second: 0, of: date)!
    }

    /// Bedtime for the night that follows `date` — always the next calendar day
    /// since the hour is past midnight.
    func bedtime(after date: Date, calendar: Calendar = .current) -> Date {
        let base = calendar.date(bySettingHour: bedHour, minute: bedMinute, second: 0, of: date)!
        return calendar.date(byAdding: .day, value: 1, to: base)!
    }

    func caffeineCutoff(on date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: caffeineCutoffHour, minute: 0, second: 0, of: date)!
    }

    func trainsOn(_ date: Date, calendar: Calendar = .current) -> Bool {
        workoutWeekdays.contains(calendar.component(.weekday, from: date))
    }

    /// The agreed default: wake 8:45 (11:45 weekends), bed 1:00 AM, caffeine
    /// done by 5 PM, train Mon–Thu.
    static var standard: RhythmPreference {
        RhythmPreference(
            weekdayWakeHour: 8, weekdayWakeMinute: 45,
            weekendWakeHour: 11, weekendWakeMinute: 45,
            bedHour: 1, bedMinute: 0,
            caffeineCutoffHour: 17,
            workoutWeekdays: [2, 3, 4, 5]
        )
    }
}
