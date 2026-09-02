import SwiftUI

struct HistoryView: View {
    let credentialStore: CredentialStore
    let boardId: String

    @State private var entries: [CredentialStore.HistoryEntry] = []
    @State private var displayedMonth: Date = {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
    }()

    private var boardURL: URL? {
        guard !boardId.isEmpty else { return nil }
        return URL(string: "https://ibm.monday.com/boards/\(boardId)")
    }

    // Dictionary keyed by "yyyy-MM-dd" for O(1) lookup in the grid
    private var entryMap: [String: AttendanceStatus] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.date, $0.status) })
    }

    private let isoParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    // Calendar starting on Monday
    private var cal: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2   // Monday
        return c
    }

    private let weekdayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// All day-numbers to display in the grid for the current month.
    /// nil = padding cell before/after the month.
    private var gridDays: [Date?] {
        guard
            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: displayedMonth)),
            let range = cal.range(of: .day, in: .month, for: monthStart)
        else { return [] }

        // weekday of the 1st, adjusted so Monday = 0
        let firstWeekday = (cal.component(.weekday, from: monthStart) - cal.firstWeekday + 7) % 7
        let totalDays = range.count
        let totalCells = Int(ceil(Double(firstWeekday + totalDays) / 7.0)) * 7

        return (0..<totalCells).map { offset -> Date? in
            let dayOffset = offset - firstWeekday
            guard dayOffset >= 0, dayOffset < totalDays else { return nil }
            return cal.date(byAdding: .day, value: dayOffset, to: monthStart)
        }
    }

    private func isoKey(for date: Date) -> String {
        isoParser.string(from: date)
    }

    private func isToday(_ date: Date) -> Bool {
        cal.isDateInToday(date)
    }

    private func isWeekend(_ date: Date) -> Bool {
        let wd = cal.component(.weekday, from: date)
        return wd == 1 || wd == 7
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ────────────────────────────────────────────────────
            HStack(spacing: 8) {
                Button { changeMonth(by: -1) } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Text(monthFormatter.string(from: displayedMonth))
                    .font(.headline)
                    .frame(minWidth: 140)

                Button { changeMonth(by: 1) } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)

                Spacer()

                if let url = boardURL {
                    Link("Open Board ↗", destination: url)
                        .font(.subheadline)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // ── Weekday column headers ─────────────────────────────────────
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(weekdayLabels, id: \.self) { label in
                    Text(label)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 16)

            Divider()

            // ── Calendar grid ─────────────────────────────────────────────
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(gridDays.enumerated()), id: \.offset) { _, date in
                    if let date {
                        DayCell(
                            day: cal.component(.day, from: date),
                            status: entryMap[isoKey(for: date)],
                            isToday: isToday(date),
                            isWeekend: isWeekend(date)
                        )
                    } else {
                        Color.clear
                            .frame(height: 52)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // ── Legend ────────────────────────────────────────────────────
            Divider()
            HStack(spacing: 16) {
                ForEach(AttendanceStatus.allCases, id: \.self) { s in
                    HStack(spacing: 4) {
                        Text(s.icon).font(.caption)
                        Text(s.menuLabel).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            // ── Footer ────────────────────────────────────────────────────
            Divider()
            HStack {
                Spacer()
                Button("Close") { NSApp.keyWindow?.close() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { entries = credentialStore.loadHistory() }
    }

    private func changeMonth(by delta: Int) {
        if let next = cal.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = next
        }
    }
}

// MARK: - Day Cell

private struct DayCell: View {
    let day: Int
    let status: AttendanceStatus?
    let isToday: Bool
    let isWeekend: Bool

    private var bgColor: Color {
        if let status {
            switch status {
            case .office:   return Color.blue.opacity(0.15)
            case .wfh:      return Color.green.opacity(0.15)
            case .sick:     return Color.orange.opacity(0.15)
            case .vacation: return Color.purple.opacity(0.15)
            case .holiday:  return Color.red.opacity(0.15)
            }
        }
        return isWeekend ? Color.primary.opacity(0.04) : Color.clear
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("\(day)")
                .font(.system(size: 12, weight: isToday ? .bold : .regular))
                .foregroundColor(isToday ? .accentColor : isWeekend ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 5)
                .padding(.top, 4)

            if let status {
                Text(status.icon)
                    .font(.system(size: 18))
                    .frame(maxWidth: .infinity)
            } else {
                Spacer()
            }

            Spacer(minLength: 0)
        }
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(bgColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isToday ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
    }
}
