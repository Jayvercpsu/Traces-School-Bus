import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/school_service.dart';
import '../auth/auth_controller.dart';

final passengerServiceStreamProvider =
    StreamProvider.autoDispose<SchoolService?>((ref) {
      final user = ref.watch(authControllerProvider);
      final repo = ref.watch(tracesRepositoryProvider);

      final serviceId = user?.assignedServiceId;
      if (serviceId == null || serviceId.isEmpty) {
        return Stream.value(null);
      }

      return repo.watchService(serviceId);
    });
