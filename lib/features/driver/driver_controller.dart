import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/traces_repository.dart';
import '../../models/attendance_record.dart';
import '../../models/school_service.dart';
import '../../models/location_point.dart';
import '../auth/auth_controller.dart';

final driverServiceStreamProvider = StreamProvider.autoDispose<SchoolService?>((
  ref,
) {
  final user = ref.watch(authControllerProvider);
  final repo = ref.watch(tracesRepositoryProvider);

  final serviceId = user?.assignedServiceId;
  if (serviceId == null || serviceId.isEmpty) {
    return Stream.value(null);
  }

  return repo.watchService(serviceId);
});

final todayAttendanceProvider =
    FutureProvider.autoDispose<List<AttendanceRecord>>((ref) {
      final user = ref.watch(authControllerProvider);
      final repo = ref.watch(tracesRepositoryProvider);

      if (user == null || user.assignedServiceId == null) {
        return Future.value([]);
      }

      return repo.getTodayAttendance(user.assignedServiceId!);
    });

class DriverController {
  DriverController(this._repo, this._ref);

  final TracesRepository _repo;
  final Ref _ref;

  Future<void> setStatus(ServiceStatus status) async {
    final user = _ref.read(authControllerProvider);
    if (user == null || user.assignedServiceId == null) return;
    final service = await _repo.getService(user.assignedServiceId!);
    if (service == null) return;

    final newEta = DateTime.now().add(const Duration(minutes: 15));
    await _repo.updateServiceStatus(service.id, status, newEta);
  }

  Future<void> updateLocation(LocationPoint location) async {
    final user = _ref.read(authControllerProvider);
    if (user == null || user.assignedServiceId == null) return;
    await _repo.updateBusLocation(user.assignedServiceId!, location);
  }

  Future<void> markAttendance(
    String passengerId,
    AttendanceStatus status,
  ) async {
    final user = _ref.read(authControllerProvider);
    if (user == null || user.assignedServiceId == null) return;
    await _repo.markAttendance(user.assignedServiceId!, passengerId, status);
    _ref.invalidate(todayAttendanceProvider);
  }
}

final driverControllerProvider = Provider<DriverController>((ref) {
  final repo = ref.watch(tracesRepositoryProvider);
  return DriverController(repo, ref);
});
