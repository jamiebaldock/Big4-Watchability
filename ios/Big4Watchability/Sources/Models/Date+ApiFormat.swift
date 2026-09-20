import Foundation

// The backend's /schedule etc. take a plain "yyyy-MM-dd" date string with no
// timezone. Android sends its device's LOCAL calendar date (java.time.
// LocalDate.now() has no timezone concept at all) - the original iOS port's
// dayFormatter used a UTC timeZone instead, which is wrong for exactly the
// same reason GameCardView's tipoff-time comment already flagged elsewhere:
// it can disagree with the device's actual local "today" near midnight
// (e.g. any time from local midnight to local UTC-offset o'clock, for a
// positive-offset timezone like Hobart's, ends up asking for "yesterday").
// Fixed here while rebuilding the multi-day paging system, which is the
// first place that actually depends on "today" being correct at the edges.
private let apiDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = .current
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

extension Date {
    var apiDateString: String { apiDateFormatter.string(from: self) }

    static func fromApiDateString(_ string: String) -> Date? {
        apiDateFormatter.date(from: string)
    }
}
