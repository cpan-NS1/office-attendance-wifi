enum CheckInState {
    case notCheckedIn
    case checkedIn(AttendanceStatus)
    case error(String)
}
