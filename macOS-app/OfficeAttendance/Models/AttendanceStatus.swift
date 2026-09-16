enum AttendanceStatus: String, CaseIterable, Codable {
    case office, wfh, wfhSickness, wfhUnplannedIssues, wfhWeatherWarning
    case sick, vacation, loa, bankHoliday, travel

    /// The string value written to Monday.com
    var mondayValue: String {
        switch self {
        case .office:               return "Office"
        case .wfh:                  return "WFH"
        case .wfhSickness:          return "WFH: Sickness"
        case .wfhUnplannedIssues:   return "WFH: Unplanned Issues"
        case .wfhWeatherWarning:    return "WFH: Weather Warning"
        case .sick:                 return "Sick"
        case .vacation:             return "Vacation"
        case .loa:                  return "LOA"
        case .bankHoliday:          return "Bank Holiday"
        case .travel:               return "Travel"
        }
    }

    var menuLabel: String {
        switch self {
        case .office:               return "Office"
        case .wfh:                  return "WFH"
        case .wfhSickness:          return "WFH: Sickness"
        case .wfhUnplannedIssues:   return "WFH: Unplanned Issues"
        case .wfhWeatherWarning:    return "WFH: Weather Warning"
        case .sick:                 return "Sick"
        case .vacation:             return "Vacation"
        case .loa:                  return "LOA"
        case .bankHoliday:          return "Bank Holiday"
        case .travel:               return "Travel"
        }
    }

    var icon: String {
        switch self {
        case .office:               return "🏢"
        case .wfh:                  return "🏠"
        case .wfhSickness:          return "🤒"
        case .wfhUnplannedIssues:   return "🔧"
        case .wfhWeatherWarning:    return "⛈️"
        case .sick:                 return "🤧"
        case .vacation:             return "🌴"
        case .loa:                  return "📋"
        case .bankHoliday:          return "🎌"
        case .travel:               return "✈️"
        }
    }
}
