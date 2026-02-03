import '../models/traces_user.dart';
import '../models/school_service.dart';
import '../models/attendance_record.dart';
import '../models/location_point.dart';

abstract class TracesRepository {
  Stream<SchoolService?> watchService(String serviceId);
  Future<SchoolService?> getService(String serviceId);

  Future<TracesUser> fakeLogin(String name, UserRole role);

  Future<SchoolService> assignUserToDemoService(TracesUser user);

  Future<void> updateBusLocation(String serviceId, LocationPoint location);
  Future<void> updateServiceStatus(
    String serviceId,
    ServiceStatus status,
    DateTime eta,
  );

  Future<List<AttendanceRecord>> getTodayAttendance(String serviceId);
  Future<void> markAttendance(
    String serviceId,
    String passengerId,
    AttendanceStatus status,
  );

  Future<void> assignPassengerToService({
    required String passengerId,
    required String serviceId,
    DateTime? dueDate,
  });

  Future<void> unassignPassengerFromService({
    required String passengerId,
    required String serviceId,
  });
}
