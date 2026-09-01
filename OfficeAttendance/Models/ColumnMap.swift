struct ColumnMap: Codable {
    var employeeColumnId: String
    var weekStartColumnId: String
    var mondayColumnId: String
    var tuesdayColumnId: String
    var wednesdayColumnId: String
    var thursdayColumnId: String
    var fridayColumnId: String

    /// Returns the column ID for the given weekday (1 = Mon … 5 = Fri).
    /// Returns nil for weekends.
    func columnId(forWeekday weekday: Int) -> String? {
        switch weekday {
        case 2: return mondayColumnId
        case 3: return tuesdayColumnId
        case 4: return wednesdayColumnId
        case 5: return thursdayColumnId
        case 6: return fridayColumnId
        default: return nil
        }
    }
}
