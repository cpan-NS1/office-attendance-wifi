enum AttendanceStatus: String, CaseIterable, Codable {
    case office, wfh, sick, vacation, holiday

    /// The string value written to Monday.com
    var mondayValue: String {
        switch self {
        case .office:   return "Office"
        case .wfh:      return "WFH"
        case .sick:     return "Sick"
        case .vacation: return "Vacation"
        case .holiday:  return "Holiday"
        }
    }

    var menuLabel: String {
        switch self {
        case .office:   return "Office"
        case .wfh:      return "WFH"
        case .sick:     return "Sick"
        case .vacation: return "Vacation"
        case .holiday:  return "Holiday"
        }
    }

    var icon: String {
        switch self {
        case .office:   return "🏢"
        case .wfh:      return "🏠"
        case .sick:     return "🤒"
        case .vacation: return "🌴"
        case .holiday:  return "🎌"
        }
    }
}
