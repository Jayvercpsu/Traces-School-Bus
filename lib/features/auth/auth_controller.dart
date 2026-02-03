import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../data/in_memory_traces_repository.dart';
import '../../data/traces_repository.dart';
import '../../models/traces_user.dart';
import '../../models/school_service.dart';

final tracesRepositoryProvider = Provider<TracesRepository>((ref) {
  return FirestoreTracesRepository();
});

final authControllerProvider =
    StateNotifierProvider<AuthController, TracesUser?>((ref) {
  final repo = ref.watch(tracesRepositoryProvider);
  return AuthController(repo, ref);
});

final currentServiceProvider = StateProvider<SchoolService?>((ref) => null);

class AuthController extends StateNotifier<TracesUser?> {
  AuthController(this._repo, this._ref) : super(null);

  final TracesRepository _repo;
  final Ref _ref;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;

  @override
  void dispose() {
    _userSub?.cancel();
    super.dispose();
  }

  void _startUserListener(String uid) {
    _userSub?.cancel();

    _userSub = _db.collection('users').doc(uid).snapshots().listen(
      (snap) async {
        if (!snap.exists) return;
        final data = snap.data() ?? {};

        final roleString = (data['role'] as String?) ?? 'passenger';
        final role = roleString == 'driver' ? UserRole.driver : UserRole.passenger;

        final assignedRaw = data['assignedServiceId'];
        final assignedServiceId =
            (assignedRaw is String && assignedRaw.trim().isNotEmpty) ? assignedRaw : null;

        final name = (data['name'] as String?) ?? (state?.name ?? '');
        final email = (data['email'] as String?) ?? state?.email;

        state = TracesUser(
          id: uid,
          name: name,
          role: role,
          assignedServiceId: assignedServiceId,
          email: email,
        );

        if (assignedServiceId == null) {
          _ref.read(currentServiceProvider.notifier).state = null;
          return;
        }

        final service = await _repo.getService(assignedServiceId);
        _ref.read(currentServiceProvider.notifier).state = service;
      },
      onError: (e) {},
    );
  }

  Future<void> register(
    WidgetRef ref, {
    required String name,
    required String email,
    required String password,
    required UserRole role,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final uid = cred.user!.uid;

    await _db.collection('users').doc(uid).set({
      'name': name,
      'email': email,
      'role': role.name,
      'assignedServiceId': null,
      'createdAt': FieldValue.serverTimestamp(),
    });

    state = TracesUser(
      id: uid,
      name: name,
      role: role,
      assignedServiceId: null,
      email: email,
    );

    _ref.read(currentServiceProvider.notifier).state = null;

    await _auth.signOut();
  }

Future<void> registerDriver(
  WidgetRef ref, {
  required String name,
  required String email,
  required String password,
  required String plateNumber,
  required String busModel,
  required String contactNumber,
}) async {
  final cred = await _auth.createUserWithEmailAndPassword(
    email: email,
    password: password,
  );

  final uid = cred.user!.uid;

  final serviceRef = _db.collection('services').doc();
  final serviceId = serviceRef.id;

  final now = DateTime.now();

  await serviceRef.set({
    'routeName': 'School Bus Route',
    'driverId': uid,
    'driverName': name,
    'driverContact': contactNumber,
    'busPlateNumber': plateNumber,
    'busModel': busModel,
    'passengerIds': <String>[],
    'currentLocation': {'latitude': 0.0, 'longitude': 0.0},
    'eta': Timestamp.fromDate(now.add(const Duration(minutes: 15))),
    'status': 'preparing',
    'paymentDueDates': <String, dynamic>{},
  });

  await _db.collection('users').doc(uid).set({
    'name': name,
    'email': email,
    'role': UserRole.driver.name,
    'assignedServiceId': serviceId,
    'plateNumber': plateNumber,
    'busModel': busModel,
    'contactNumber': contactNumber,
    'createdAt': FieldValue.serverTimestamp(),
  });

  state = TracesUser(
    id: uid,
    name: name,
    role: UserRole.driver,
    assignedServiceId: serviceId,
    email: email,
  );

  final service = await _repo.getService(serviceId);
  _ref.read(currentServiceProvider.notifier).state = service;

  await _auth.signOut();
}


  Future<void> login(
    WidgetRef ref, {
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final firebaseUser = cred.user;
      if (firebaseUser == null) {
        throw FirebaseAuthException(
          code: 'no-user',
          message: 'User not found.',
        );
      }

      final uid = firebaseUser.uid;

      final snapshot = await _db.collection('users').doc(uid).get();
      if (!snapshot.exists) {
        await _auth.signOut();
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'User profile not found. Please register again.',
        );
      }

      final data = snapshot.data()!;
      final roleString = (data['role'] as String?) ?? 'passenger';
      final role = roleString == 'driver' ? UserRole.driver : UserRole.passenger;

      final assignedRaw = data['assignedServiceId'];
      final assignedServiceId =
          (assignedRaw is String && assignedRaw.trim().isNotEmpty) ? assignedRaw : null;

      final name = (data['name'] as String?) ?? (firebaseUser.email ?? 'User');

      state = TracesUser(
        id: uid,
        name: name,
        role: role,
        assignedServiceId: assignedServiceId,
        email: (data['email'] as String?) ?? email,
      );

      if (assignedServiceId == null) {
        _ref.read(currentServiceProvider.notifier).state = null;
      } else {
        final service = await _repo.getService(assignedServiceId);
        _ref.read(currentServiceProvider.notifier).state = service;
      }

      _startUserListener(uid);
    } on FirebaseAuthException {
      rethrow;
    } on FirebaseException catch (e) {
      throw FirebaseAuthException(
        code: e.code,
        message: e.message,
      );
    }
  }

  Future<void> logout(WidgetRef ref) async {
    await _userSub?.cancel();
    _userSub = null;

    await _auth.signOut();
    state = null;
    _ref.read(currentServiceProvider.notifier).state = null;
  }
}
