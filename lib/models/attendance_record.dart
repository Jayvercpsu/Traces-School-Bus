enum AttendanceStatus { present, absent }

class AttendanceRecord {
  final String passengerId;
  final DateTime date;
  final AttendanceStatus status;

  AttendanceRecord({
    required this.passengerId,
    required this.date,
    required this.status,
  });
}
