import SwiftUI

// Swift mirror of SeasonCalendarDialog.kt - a bespoke month-grid date picker
// (not the system DatePicker, which can't decorate day cells with a per-day
// game count). Simplified from Android's version: chevron-tap month
// navigation only, not also a swipeable month pager - the tap interaction is
// the same either way, this just skips replicating a second pager on top of
// the day pager this same screen already has.
struct SeasonCalendarView: View {
    let initialMonth: Date
    let onMonthChanged: (Date) -> Void
    let onDateSelected: (Date) -> Void

    // Observed directly (not snapshotted into plain `let` properties at
    // sheet-presentation time) - counts load asynchronously after the sheet
    // already appears, and a `.sheet` content closure's captured values
    // don't reliably refresh once presented. Observing the view model here
    // means Combine's own publisher drives the re-render instead, which
    // works regardless of that timing.
    @ObservedObject var viewModel: GamesViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @State private var currentMonth: Date

    init(
        initialMonth: Date,
        viewModel: GamesViewModel,
        onMonthChanged: @escaping (Date) -> Void,
        onDateSelected: @escaping (Date) -> Void
    ) {
        self.initialMonth = initialMonth
        self.viewModel = viewModel
        self.onMonthChanged = onMonthChanged
        self.onDateSelected = onDateSelected
        _currentMonth = State(initialValue: initialMonth)
    }

    private static let calendar = Calendar.current
    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()
    private static let weekdaySymbols: [String] = {
        let symbols = DateFormatter().veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        return symbols
    }()

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    changeMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                HStack(spacing: 8) {
                    Text(Self.monthYearFormatter.string(from: currentMonth))
                        .font(.title3.bold())
                        .foregroundStyle(theme.textPrimary)
                    if viewModel.isLoadingMonthCounts && !Calendar.current.isDate(viewModel.monthCountsMonth ?? .distantPast, equalTo: currentMonth, toGranularity: .month) {
                        ProgressView().scaleEffect(0.7)
                    }
                }
                Spacer()
                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
            }
            .foregroundStyle(theme.textPrimary)

            HStack(spacing: 0) {
                ForEach(Array(Self.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.bold())
                        .foregroundStyle(theme.textMuted)
                        .frame(maxWidth: .infinity)
                }
            }

            monthGrid
        }
        .padding(20)
        .background(theme.surfaceCardElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.backgroundBase.ignoresSafeArea())
        .onAppear { onMonthChanged(currentMonth) }
    }

    private var monthGrid: some View {
        let calendar = Self.calendar
        let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)) ?? currentMonth
        // weekday: 1=Sunday...7=Saturday - remap to a 0-based Sunday-first offset.
        let leadingBlanks = calendar.component(.weekday, from: firstOfMonth) - 1
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30
        let showCounts = viewModel.monthCountsMonth.map { calendar.isDate($0, equalTo: currentMonth, toGranularity: .month) } ?? false

        return VStack(spacing: 4) {
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        let dayNum = row * 7 + col - leadingBlanks + 1
                        if dayNum >= 1 && dayNum <= daysInMonth {
                            let date = calendar.date(byAdding: .day, value: dayNum - 1, to: firstOfMonth) ?? firstOfMonth
                            CalendarDayCell(
                                date: date,
                                gameCount: showCounts ? viewModel.monthCounts[date.apiDateString] : nil,
                                onTap: {
                                    dismiss()
                                    onDateSelected(date)
                                }
                            )
                            .frame(maxWidth: .infinity)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: 40)
                        }
                    }
                }
            }
        }
    }

    private func changeMonth(by delta: Int) {
        guard let newMonth = Self.calendar.date(byAdding: .month, value: delta, to: currentMonth) else { return }
        currentMonth = newMonth
        onMonthChanged(newMonth)
    }
}

private struct CalendarDayCell: View {
    let date: Date
    let gameCount: Int?
    let onTap: () -> Void

    @Environment(\.appTheme) private var theme

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.subheadline)
                    .foregroundStyle(theme.textPrimary)
                Text(gameCount.map(String.init) ?? " ")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.tierWorthYourTime)
            }
            .frame(width: 36, height: 40)
            .background(isToday ? AppColors.tierWorthYourTime.opacity(0.25) : Color.clear, in: Circle())
        }
        .buttonStyle(.plain)
    }
}
