import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/traces_user.dart';
import '../models/school_service.dart';
import '../models/location_point.dart';
import '../models/attendance_record.dart';
import 'traces_repository.dart';

class FirestoreTracesRepository implements TracesRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  Stream<SchoolService?> watchService(String serviceId) {
    debugPrint('watchService() listening for service: $serviceId');

    return _db.collection('services').doc(serviceId).snapshots().asyncMap((
      snapshot,
    ) async {
      if (!snapshot.exists) {
        debugPrint('watchService(): service $serviceId DOES NOT EXIST');
        return null;
      }

      final baseService = _serviceFromFirestore(snapshot);

      try {
        final driverQuery = await _db
            .collection('users')
            .where('role', isEqualTo: 'driver')
            .where('assignedServiceId', isEqualTo: serviceId)
            .limit(1)
            .get();

        if (driverQuery.docs.isNotEmpty) {
          final driverDoc = driverQuery.docs.first;
          final driverData = driverDoc.data();

          return baseService.copyWith(
            driverId: driverDoc.id,
            driverName: (driverData['name'] as String?) ?? baseService.driverName,
            driverContact: (driverData['contactNumber'] as String?) ?? baseService.driverContact,
            busPlateNumber: (driverData['plateNumber'] as String?) ?? baseService.busPlateNumber,
            busModel: (driverData['busModel'] as String?) ?? baseService.busModel,
          );
        }
      } catch (e, st) {
        debugPrint('watchService(): error while fetching driver: $e');
        debugPrint(st.toString());
      }

      return baseService;
    });
  }

  @override
  Future<SchoolService?> getService(String serviceId) async {
    debugPrint('getService() fetching service: $serviceId');

    final snapshot = await _db.collection('services').doc(serviceId).get();
    if (!snapshot.exists) {
      debugPrint('getService(): service $serviceId DOES NOT EXIST');
      return null;
    }

    final baseService = _serviceFromFirestore(snapshot);

    try {
      final driverQuery = await _db
          .collection('users')
          .where('role', isEqualTo: 'driver')
          .where('assignedServiceId', isEqualTo: serviceId)
          .limit(1)
          .get();

      if (driverQuery.docs.isNotEmpty) {
        final driverDoc = driverQuery.docs.first;
        final driverData = driverDoc.data();

        return baseService.copyWith(
          driverId: driverDoc.id,
          driverName: (driverData['name'] as String?) ?? baseService.driverName,
          driverContact: (driverData['contactNumber'] as String?) ?? baseService.driverContact,
          busPlateNumber: (driverData['plateNumber'] as String?) ?? baseService.busPlateNumber,
          busModel: (driverData['busModel'] as String?) ?? baseService.busModel,
        );
      }
    } catch (e, st) {
      debugPrint('getService(): error while fetching driver: $e');
      debugPrint(st.toString());
    }

    return baseService;
  }

  @override
  Future<TracesUser> fakeLogin(String name, UserRole role) async {
    throw UnimplementedError('Use Firebase Auth instead');
  }

  @override
  Future<SchoolService> assignUserToDemoService(TracesUser user) async {
    debugPrint('assignUserToDemoService called for user: ${user.id} role: ${user.role}');

    const serviceId = 'service_1';
    final serviceRef = _db.collection('services').doc(serviceId);

    final snapshot = await serviceRef.get();
    final now = DateTime.now();

    if (!snapshot.exists) {
      await serviceRef.set({
        'routeName': 'School Bus Route',
        'driverId': '',
        'driverName': '',
        'driverContact': '',
        'busPlateNumber': '',
        'busModel': '',
        'passengerIds': [],
        'currentLocation': {'latitude': 0.0, 'longitude': 0.0},
        'eta': Timestamp.fromDate(now.add(const Duration(minutes: 15))),
        'status': 'preparing',
        'paymentDueDates': {},
      });
    }

    return _serviceFromFirestore(await serviceRef.get());
  }

  @override
  Future<void> assignPassengerToService({
    required String passengerId,
    required String serviceId,
    DateTime? dueDate,
  }) async {
    final serviceRef = _db.collection('services').doc(serviceId);
    final userRef = _db.collection('users').doc(passengerId);

    final now = DateTime.now();
    final effectiveDue = dueDate ?? now.add(const Duration(days: 7));

    await _db.runTransaction((tx) async {
      final serviceSnap = await tx.get(serviceRef);
      if (!serviceSnap.exists) {
        throw Exception('Service not found: $serviceId');
      }

      final userSnap = await tx.get(userRef);
      if (!userSnap.exists) {
        throw Exception('Passenger not found: $passengerId');
      }

      final serviceData = serviceSnap.data() as Map<String, dynamic>;
      final passengerIds = List<String>.from(serviceData['passengerIds'] ?? []);
      if (!passengerIds.contains(passengerId)) {
        passengerIds.add(passengerId);
      }

      final paymentDueDates = Map<String, dynamic>.from(serviceData['paymentDueDates'] ?? {});
      paymentDueDates[passengerId] = Timestamp.fromDate(effectiveDue);

      tx.update(serviceRef, {
        'passengerIds': passengerIds,
        'paymentDueDates': paymentDueDates,
      });

      tx.update(userRef, {
        'assignedServiceId': serviceId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<void> unassignPassengerFromService({
    required String passengerId,
    required String serviceId,
  }) async {
    final serviceRef = _db.collection('services').doc(serviceId);
    final userRef = _db.collection('users').doc(passengerId);

    await _db.runTransaction((tx) async {
      final serviceSnap = await tx.get(serviceRef);
      if (!serviceSnap.exists) {
        throw Exception('Service not found: $serviceId');
      }

      final serviceData = serviceSnap.data() as Map<String, dynamic>;
      final passengerIds = List<String>.from(serviceData['passengerIds'] ?? []);
      passengerIds.remove(passengerId);

      final paymentDueDates = Map<String, dynamic>.from(serviceData['paymentDueDates'] ?? {});
      paymentDueDates.remove(passengerId);

      tx.update(serviceRef, {
        'passengerIds': passengerIds,
        'paymentDueDates': paymentDueDates,
      });

      tx.update(userRef, {
        'assignedServiceId': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<void> updateBusLocation(String serviceId, LocationPoint location) async {
    await _db.collection('services').doc(serviceId).update({
      'currentLocation': {
        'latitude': location.latitude,
        'longitude': location.longitude,
      },
    });
  }

  @override
  Future<void> updateServiceStatus(String serviceId, ServiceStatus status, DateTime eta) async {
    await _db.collection('services').doc(serviceId).update({
      'status': status.name,
      'eta': Timestamp.fromDate(eta),
    });
  }

  @override
  Future<List<AttendanceRecord>> getTodayAttendance(String serviceId) async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final snapshot = await _db
        .collection('services')
        .doc(serviceId)
        .collection('attendance')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('date', isLessThan: Timestamp.fromDate(endOfDay))
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return AttendanceRecord(
        passengerId: data['passengerId'] as String,
        date: (data['date'] as Timestamp).toDate(),
        status: AttendanceStatus.values.firstWhere(
          (e) => e.name == data['status'],
          orElse: () => AttendanceStatus.absent,
        ),
      );
    }).toList();
  }

  @override
  Future<void> markAttendance(String serviceId, String passengerId, AttendanceStatus status) async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    await _db
        .collection('services')
        .doc(serviceId)
        .collection('attendance')
        .doc('${passengerId}_${startOfDay.millisecondsSinceEpoch}')
        .set({
      'passengerId': passengerId,
      'date': Timestamp.fromDate(today),
      'status': status.name,
    });
  }

  SchoolService _serviceFromFirestore(DocumentSnapshot snapshot) {
    final data = snapshot.data() as Map<String, dynamic>;

    final locationData = data['currentLocation'] as Map<String, dynamic>;
    final location = LocationPoint(
      latitude: (locationData['latitude'] as num).toDouble(),
      longitude: (locationData['longitude'] as num).toDouble(),
    );

    LocationPoint? destinationLocation;
    if (data['destinationLocation'] != null) {
      final destData = data['destinationLocation'] as Map<String, dynamic>;
      destinationLocation = LocationPoint(
        latitude: (destData['latitude'] as num).toDouble(),
        longitude: (destData['longitude'] as num).toDouble(),
      );
    }

    final paymentDueDatesRaw = data['paymentDueDates'] as Map<String, dynamic>? ?? {};
    final paymentDueDates = <String, DateTime>{};
    paymentDueDatesRaw.forEach((key, value) {
      if (value is Timestamp) {
        paymentDueDates[key] = value.toDate();
      }
    });

    final etaValue = data['eta'];
    final eta = etaValue is Timestamp ? etaValue.toDate() : DateTime.now().add(const Duration(minutes: 15));

    final statusRaw = (data['status'] ?? 'preparing').toString();

    return SchoolService(
      id: snapshot.id,
      routeName: (data['routeName'] as String?) ?? 'School Bus Route',
      driverId: (data['driverId'] as String?) ?? '',
      driverName: (data['driverName'] as String?) ?? '',
      driverContact: (data['driverContact'] as String?) ?? '',
      busPlateNumber: (data['busPlateNumber'] as String?) ?? '',
      busModel: (data['busModel'] as String?) ?? '',
      passengerIds: List<String>.from(data['passengerIds'] ?? []),
      currentLocation: location,
      destinationLocation: destinationLocation,
      eta: eta,
      status: ServiceStatus.values.firstWhere(
        (e) => e.name == statusRaw,
        orElse: () => ServiceStatus.preparing,
      ),
      paymentDueDates: paymentDueDates,
    );
  }
}
