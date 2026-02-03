import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/animation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../models/location_point.dart';
import '../../models/school_service.dart' as school;
import '../../models/traces_user.dart';
import '../../services/route_service.dart';
import '../../services/email_service.dart';
import '../auth/auth_controller.dart';
import 'assigned_students_screen.dart';
import 'attendance_screen.dart';
import 'driver_controller.dart';
import 'driver_profile_screen.dart';
import 'driver_payment_screen.dart';

final isDrivingProvider = StateProvider<bool>((ref) => false);
final destinationProvider = StateProvider<LatLng?>((ref) => null);
final routePolylineProvider = StateProvider<List<LatLng>>((ref) => []);
final driverGpsProvider = StateProvider<LatLng?>((ref) => null);

final isMapExpandedProvider = StateProvider<bool>((ref) => false);
final followModeProvider = StateProvider<bool>((ref) => true);

final _driverTabProvider = StateProvider<int>((ref) => 0);

class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen>
    with SingleTickerProviderStateMixin {
  StreamSubscription<Position>? _positionSubscription;
  Stream<Position>? _positionStream;
  MapController? _mapController;

  bool _isStartingDrive = false;
  bool _creatingService = false;

  bool _mapReady = false;
  AnimationController? _camAnim;

  BoxDecoration _bg() {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.blue.shade400,
          Colors.blue.shade600,
          Colors.blue.shade800,
        ],
      ),
    );
  }

  Widget _glassCard({
    required Widget child,
    EdgeInsets? padding,
    Color? color,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: (color ?? Colors.white).withValues(alpha: 0.92),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _camAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _checkAndRequestLocationPermission();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final u = ref.read(authControllerProvider);
      if (u != null) {
        await _ensureDriverHasService(u);
      }
      await _startPassiveLocationTracking();
    });
  }

  Future<void> _ensureDriverHasService(TracesUser user) async {
    if (!mounted) return;
    if (user.role != UserRole.driver) return;

    final serviceId = user.assignedServiceId;
    if (serviceId != null && serviceId.trim().isNotEmpty) return;

    if (_creatingService) return;
    setState(() => _creatingService = true);

    try {
      final db = FirebaseFirestore.instance;

      final userSnap = await db.collection('users').doc(user.id).get();
      final userData = userSnap.data() ?? {};

      final plateNumber = (userData['plateNumber'] as String?) ?? '';
      final busModel = (userData['busModel'] as String?) ?? '';
      final contactNumber = (userData['contactNumber'] as String?) ?? '';

      final serviceRef = db.collection('services').doc();
      final now = DateTime.now();

      await serviceRef.set({
        'routeName': 'School Bus Route',
        'driverId': user.id,
        'driverName': user.name,
        'driverContact': contactNumber,
        'busPlateNumber': plateNumber,
        'busModel': busModel,
        'passengerIds': <String>[],
        'currentLocation': {'latitude': 0.0, 'longitude': 0.0},
        'eta': Timestamp.fromDate(now.add(const Duration(minutes: 15))),
        'status': 'preparing',
        'paymentDueDates': <String, dynamic>{},
        'destinationLocation': null,
      });

      await db.collection('users').doc(user.id).update({
        'assignedServiceId': serviceRef.id,
      });
    } finally {
      if (mounted) setState(() => _creatingService = false);
    }
  }

  Future<void> _checkAndRequestLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        _showLocationSettingsDialog(
          title: 'Location Service Disabled',
          message:
              'Please enable location services in your device settings to use this app.',
          isServiceIssue: true,
        );
      }
      return;
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          _showLocationSettingsDialog(
            title: 'Location Permission Denied',
            message:
                'This app needs location permission to track and update your location. Please allow location access.',
            isServiceIssue: false,
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        _showLocationSettingsDialog(
          title: 'Location Permission Permanently Denied',
          message:
              'Location permissions are permanently denied. Please go to app settings and enable location access manually.',
          isServiceIssue: false,
          isPermanentlyDenied: true,
        );
      }
      return;
    }
  }

  void _showLocationSettingsDialog({
    required String title,
    required String message,
    required bool isServiceIssue,
    bool isPermanentlyDenied = false,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.location_off, color: Colors.red.shade700, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 18))),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              if (isPermanentlyDenied) {
                await Geolocator.openAppSettings();
              } else if (isServiceIssue) {
                await Geolocator.openLocationSettings();
              } else {
                _checkAndRequestLocationPermission();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
            ),
            child: Text(
              isPermanentlyDenied || isServiceIssue ? 'Open Settings' : 'Allow',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startPassiveLocationTracking() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever)
        return;

      final initial = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final initialLatLng = LatLng(initial.latitude, initial.longitude);
      ref.read(driverGpsProvider.notifier).state = initialLatLng;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_mapReady) _safeAnimatedMove(initialLatLng, 16);
      });

      const settings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      );

      _positionSubscription?.cancel();
      _positionSubscription =
          Geolocator.getPositionStream(locationSettings: settings).listen((
            pos,
          ) async {
            final latLng = LatLng(pos.latitude, pos.longitude);
            ref.read(driverGpsProvider.notifier).state = latLng;

            final follow = ref.read(followModeProvider);
            if (_mapReady && follow) {
              _safeMove(latLng, _mapController!.camera.zoom);
            }

            final user = ref.read(authControllerProvider);
            if (user != null &&
                user.assignedServiceId != null &&
                user.assignedServiceId!.trim().isNotEmpty) {
              final driverCtrl = ref.read(driverControllerProvider);
              await driverCtrl.updateLocation(
                LocationPoint(latitude: pos.latitude, longitude: pos.longitude),
              );
            }
          }, onError: (e) => debugPrint('Location stream error: $e'));
    } catch (e) {
      debugPrint('Passive tracking failed: $e');
    }
  }

  void _safeMove(LatLng center, double zoom) {
    if (_mapController == null) return;
    if (!_mapReady) return;
    _mapController!.move(center, zoom);
  }

  void _safeAnimatedMove(LatLng to, double zoom) {
    if (_mapController == null) return;
    if (!_mapReady) return;
    if (_camAnim == null) return;

    final fromCenter = _mapController!.camera.center;
    final fromZoom = _mapController!.camera.zoom;

    _camAnim!.stop();
    _camAnim!.reset();

    final curve = CurvedAnimation(
      parent: _camAnim!,
      curve: Curves.easeInOutCubic,
    );

    final latTween = Tween<double>(
      begin: fromCenter.latitude,
      end: to.latitude,
    );
    final lngTween = Tween<double>(
      begin: fromCenter.longitude,
      end: to.longitude,
    );
    final zoomTween = Tween<double>(begin: fromZoom, end: zoom);

    void tick() {
      final t = curve.value;
      final c = LatLng(latTween.transform(t), lngTween.transform(t));
      final z = zoomTween.transform(t);
      _mapController!.move(c, z);
    }

    void done() {
      _camAnim!.removeListener(tick);
      _camAnim!.removeStatusListener((_) {});
    }

    _camAnim!.addListener(tick);
    _camAnim!.addStatusListener((s) {
      if (s == AnimationStatus.completed || s == AnimationStatus.dismissed) {
        done();
      }
    });

    _camAnim!.forward();
  }

  LatLng? _routeCenter(List<LatLng> pts) {
    if (pts.isEmpty) return null;
    double lat = 0;
    double lng = 0;
    for (final p in pts) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / pts.length, lng / pts.length);
  }

  Future<void> _fitRouteAnimated() async {
    if (!_mapReady || _mapController == null) return;
    final route = ref.read(routePolylineProvider);
    if (route.isEmpty) return;

    final center = _routeCenter(route);
    if (center == null) return;

    _safeAnimatedMove(center, 13.8);
    await Future.delayed(const Duration(milliseconds: 520));
  }

  void _centerToLatestGPS() {
    final gps = ref.read(driverGpsProvider);
    if (gps == null) return;
    _safeAnimatedMove(gps, 16.2);
  }

  Future<void> _showDestinationDialog() async {
    final current = ref.read(driverGpsProvider);
    final currentPosition = current ?? LatLng(0, 0);

    final result = await showGeneralDialog<LatLng>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'set destination',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, anim1, anim2) {
        return _DestinationPickerDialog(initialCenter: currentPosition);
      },
      transitionBuilder: (ctx, anim, _, child) {
        return Transform.scale(
          scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack).value,
          child: child,
        );
      },
    );

    if (result != null) {
      ref.read(destinationProvider.notifier).state = result;

      final user = ref.read(authControllerProvider);
      if (user != null && user.assignedServiceId != null) {
        await FirebaseFirestore.instance
            .collection('services')
            .doc(user.assignedServiceId!)
            .update({
              'destinationLocation': {
                'latitude': result.latitude,
                'longitude': result.longitude,
              },
            });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Destination set!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _generateRouteFromGps(LatLng destination) async {
    final gps = ref.read(driverGpsProvider);
    if (gps == null) return;
    final route = await RouteService.getRoute(gps, destination);
    ref.read(routePolylineProvider.notifier).state = route;
  }

  Future<void> _generateRoute(
    school.SchoolService service,
    LatLng destination,
  ) async {
    final gps = ref.read(driverGpsProvider);
    if (gps == null) return;
    final route = await RouteService.getRoute(gps, destination);
    ref.read(routePolylineProvider.notifier).state = route;
  }

  Future<void> _startDriving(school.SchoolService service) async {
    if (_isStartingDrive) return;

    setState(() => _isStartingDrive = true);

    final driverCtrl = ref.read(driverControllerProvider);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enable location services'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission denied'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permissions are permanently denied'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final destination = ref.read(destinationProvider);
      if (destination == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please set a destination first'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      await _generateRoute(service, destination);

      ref.read(isDrivingProvider.notifier).state = true;
      await driverCtrl.setStatus(school.ServiceStatus.onTheWay);

      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );

      _positionStream = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      );

      final double arriveThresholdMeters = 60.0;

      _positionSubscription = _positionStream?.listen((position) async {
        final currentLatLng = LatLng(position.latitude, position.longitude);

        final location = LocationPoint(
          latitude: position.latitude,
          longitude: position.longitude,
        );
        await driverCtrl.updateLocation(location);

        final dist = const Distance().as(
          LengthUnit.Meter,
          currentLatLng,
          destination,
        );

        if (dist <= arriveThresholdMeters) {
          await _positionSubscription?.cancel();
          _positionSubscription = null;
          _positionStream = null;

          await driverCtrl.setStatus(school.ServiceStatus.arrived);

          if (mounted) {
            showGeneralDialog(
              context: context,
              barrierDismissible: true,
              barrierLabel: 'arrived',
              barrierColor: Colors.black.withValues(alpha: 0.35),
              transitionDuration: const Duration(milliseconds: 280),
              pageBuilder: (ctx, a1, a2) {
                return Center(
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: MediaQuery.of(ctx).size.width * 0.82,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 22,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.green.shade50,
                            ),
                            child: const Icon(
                              Icons.flag_rounded,
                              color: Colors.green,
                              size: 44,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Arrived!',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'You have reached your destination.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'OK',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              transitionBuilder: (ctx, anim, _, child) {
                final curved = CurvedAnimation(
                  parent: anim,
                  curve: Curves.easeOutBack,
                );
                return Transform.scale(
                  scale: curved.value,
                  child: Opacity(opacity: anim.value, child: child),
                );
              },
            );
          }

          ref.read(routePolylineProvider.notifier).state = [];
          ref.read(destinationProvider.notifier).state = null;
          ref.read(isDrivingProvider.notifier).state = false;

          if (_mapController != null && mounted) {
            _mapController!.move(currentLatLng, 16);
          }

          return;
        }

        final user = ref.read(authControllerProvider);
        if (user != null && user.assignedServiceId != null) {
          final serviceDoc = await FirebaseFirestore.instance
              .collection('services')
              .doc(user.assignedServiceId!)
              .get();

          if (serviceDoc.exists) {
            final serviceData = serviceDoc.data()!;
            final etaTimestamp = serviceData['eta'] as Timestamp?;
            if (etaTimestamp != null) {
              final eta = etaTimestamp.toDate();
              final minutesUntilArrival = eta
                  .difference(DateTime.now())
                  .inMinutes;

              if (minutesUntilArrival <= 5 && minutesUntilArrival >= 4) {
                await EmailService.sendBusArrivingSoonNotifications(
                  user.assignedServiceId!,
                );
              }
            }
          }
        }

        if (_mapController != null && mounted) {
          _mapController!.move(currentLatLng, _mapController!.camera.zoom);
        }
      }, onError: (error) => debugPrint('Location error: $error'));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS tracking started! Passengers will be notified.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isStartingDrive = false);
    }
  }

  Future<void> _stopDriving() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _positionStream = null;

    ref.read(isDrivingProvider.notifier).state = false;
    ref.read(isMapExpandedProvider.notifier).state = false;
    ref.read(followModeProvider.notifier).state = true;
    ref.read(routePolylineProvider.notifier).state = [];
    ref.read(destinationProvider.notifier).state = null;

    await ref
        .read(driverControllerProvider)
        .setStatus(school.ServiceStatus.completed);

    final user = ref.read(authControllerProvider);
    if (user != null && user.assignedServiceId != null) {
      await FirebaseFirestore.instance
          .collection('services')
          .doc(user.assignedServiceId!)
          .update({'destinationLocation': null});
    }

    final gps = ref.read(driverGpsProvider);
    if (gps != null && _mapController != null && _mapReady) {
      _safeAnimatedMove(gps, 16);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Drive completed! Map cleared.'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout == true && context.mounted) {
      await ref.read(authControllerProvider.notifier).logout(ref);
      if (context.mounted) Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _camAnim?.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<TracesUser?>(authControllerProvider, (prev, next) {
      if (next == null) return;
      if (prev?.assignedServiceId != next.assignedServiceId || prev == null) {
        _ensureDriverHasService(next);
      }
    });

    final serviceStream = ref.watch(driverServiceStreamProvider);
    final user = ref.watch(authControllerProvider);
    final tab = ref.watch(_driverTabProvider);

    return serviceStream.when(
      data: (service) {
        return Container(
          decoration: _bg(),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              title: const Text('Driver'),
              backgroundColor: Colors.transparent,
              elevation: 0,
              foregroundColor: Colors.white,
              actions: [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onSelected: (value) async {
                    if (value == 'profile') {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DriverProfileScreen(),
                        ),
                      );
                    } else if (value == 'logout') {
                      await _confirmLogout(context);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'profile',
                      child: Row(
                        children: [
                          Icon(Icons.person_outline),
                          SizedBox(width: 12),
                          Text('Profile'),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'logout',
                      child: Row(
                        children: [
                          Icon(Icons.logout, color: Colors.red),
                          SizedBox(width: 12),
                          Text('Logout', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
bottomNavigationBar: BottomNavigationBar(
              currentIndex: tab,
              onTap: (i) => ref.read(_driverTabProvider.notifier).state = i,
              type: BottomNavigationBarType.fixed,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
                BottomNavigationBarItem(icon: Icon(Icons.people_alt_rounded), label: 'Assigned'),
                BottomNavigationBarItem(icon: Icon(Icons.checklist_rounded), label: 'Today'),
                BottomNavigationBarItem(icon: Icon(Icons.payments_rounded), label: 'Payment'),
              ],
            ),
            body: SafeArea(
              child: Builder(
                builder: (context) {
                  if (tab == 1) return const AssignedStudentsScreen();
                  if (tab == 2) return const AttendanceScreen();
                  if (tab == 3) return const DriverPaymentScreen();

                  if (user == null) {
                    return Center(
                      child: _glassCard(
                        child: const Text(
                          'User not logged in',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    );
                  }

                  if (user.role == UserRole.driver &&
                      (user.assignedServiceId == null ||
                          user.assignedServiceId!.trim().isEmpty ||
                          _creatingService)) {
                    return Center(
                      child: _glassCard(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Setting up your service...',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (service == null) {
                    return Center(
                      child: _glassCard(
                        child: const Text(
                          'Loading service...',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    );
                  }

                  final isDriving = ref.watch(isDrivingProvider);
                  final destination = ref.watch(destinationProvider);
                  final polyline = ref.watch(routePolylineProvider);
                  final gps = ref.watch(driverGpsProvider);
                  final expanded = ref.watch(isMapExpandedProvider);
                  final follow = ref.watch(followModeProvider);

                  final markerPoint =
                      gps ??
                      LatLng(
                        service.currentLocation.latitude,
                        service.currentLocation.longitude,
                      );

                  final statusText = switch (service.status) {
                    school.ServiceStatus.preparing => 'Preparing',
                    school.ServiceStatus.onTheWay => '🚌 On the Way',
                    school.ServiceStatus.arrived => '✅ Arrived',
                    school.ServiceStatus.completed => 'Completed',
                  };

                  final statusColor = switch (service.status) {
                    school.ServiceStatus.preparing => Colors.orange,
                    school.ServiceStatus.onTheWay => Colors.blue,
                    school.ServiceStatus.arrived => Colors.green,
                    school.ServiceStatus.completed => Colors.grey,
                  };

                  final mapHeight = expanded ? double.infinity : 360.0;

                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        if (!expanded)
                          _glassCard(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    Icons.route,
                                    color: statusColor,
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        service.routeName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'ETA: ${DateFormat('h:mm a').format(service.eta)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: statusColor.withValues(
                                        alpha: 0.25,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    statusText,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (!expanded) const SizedBox(height: 14),

                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeInOut,
                              height: mapHeight,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                              child: Stack(
                                children: [
                                  FlutterMap(
                                    mapController: _mapController,
                                    options: MapOptions(
                                      initialCenter: markerPoint,
                                      initialZoom: 16,
                                      onMapReady: () {
                                        if (_mapReady) return;
                                        _mapReady = true;
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                              final g = ref.read(
                                                driverGpsProvider,
                                              );
                                              if (g != null)
                                                _safeAnimatedMove(g, 16);
                                            });
                                      },
                                      onPositionChanged: (pos, _) {
                                        if (!follow) return;
                                      },
                                    ),
                                    children: [
                                      TileLayer(
                                        urlTemplate:
                                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                        userAgentPackageName:
                                            'com.example.traces',
                                      ),
                                      if (polyline.isNotEmpty)
                                        PolylineLayer(
                                          polylines: [
                                            Polyline(
                                              points: polyline,
                                              strokeWidth: 4,
                                              color: Colors.blue,
                                            ),
                                          ],
                                        ),
                                      MarkerLayer(
                                        markers: [
                                          Marker(
                                            point: markerPoint,
                                            width: 90,
                                            height: 90,
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Image.asset(
                                                  'assets/images/school_bus.png',
                                                  width: 44,
                                                  height: 44,
                                                ),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.blueAccent,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                  child: const Text(
                                                    'You',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (destination != null)
                                            Marker(
                                              point: destination,
                                              width: 90,
                                              height: 90,
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.location_on,
                                                    color: Colors.red,
                                                    size: 44,
                                                  ),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 3,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.red,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            10,
                                                          ),
                                                    ),
                                                    child: const Text(
                                                      'End',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),

                                  Positioned(
                                    right: 12,
                                    bottom: 12,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Material(
                                          shape: const CircleBorder(),
                                          elevation: 3,
                                          color: Colors.white,
                                          child: IconButton(
                                            icon: Icon(
                                              Icons.center_focus_strong,
                                              color: follow
                                                  ? Colors.blue
                                                  : Colors.grey.shade600,
                                            ),
                                            onPressed: () =>
                                                ref
                                                        .read(
                                                          followModeProvider
                                                              .notifier,
                                                        )
                                                        .state =
                                                    !follow,
                                            tooltip: follow
                                                ? 'Following ON'
                                                : 'Following OFF',
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Material(
                                          shape: const CircleBorder(),
                                          elevation: 3,
                                          color: Colors.white,
                                          child: IconButton(
                                            icon: const Icon(
                                              Icons.route,
                                              color: Colors.blue,
                                            ),
                                            onPressed: _fitRouteAnimated,
                                            tooltip: 'Route view',
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Material(
                                          shape: const CircleBorder(),
                                          elevation: 3,
                                          color: Colors.white,
                                          child: IconButton(
                                            icon: const Icon(
                                              Icons.my_location,
                                              color: Colors.blue,
                                            ),
                                            onPressed: _centerToLatestGPS,
                                            tooltip: 'My location',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  Positioned(
                                    left: 12,
                                    bottom: 12,
                                    child: Material(
                                      shape: const CircleBorder(),
                                      elevation: 3,
                                      color: Colors.white,
                                      child: IconButton(
                                        icon: Icon(
                                          expanded
                                              ? Icons.fullscreen_exit
                                              : Icons.fullscreen,
                                          color: Colors.blue,
                                        ),
                                        onPressed: () =>
                                            ref
                                                    .read(
                                                      isMapExpandedProvider
                                                          .notifier,
                                                    )
                                                    .state =
                                                !expanded,
                                        tooltip: expanded
                                            ? 'Exit full screen'
                                            : 'Full screen',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        if (!expanded) const SizedBox(height: 14),

                        if (!expanded)
                          _glassCard(
                            color: Colors.white,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isDriving ? Icons.stop : Icons.play_arrow,
                                  size: 44,
                                  color: isDriving ? Colors.red : Colors.blue,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  isDriving
                                      ? 'Driving in Progress'
                                      : 'Ready to Start',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 12),
                                if (!isDriving && destination == null)
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: ElevatedButton.icon(
                                      onPressed: _showDestinationDialog,
                                      icon: const Icon(Icons.location_on),
                                      label: const Text(
                                        'Set Destination',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (!isDriving && destination != null)
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: ElevatedButton.icon(
                                      onPressed: _isStartingDrive
                                          ? null
                                          : () => _startDriving(service),
                                      icon: _isStartingDrive
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(Icons.navigation),
                                      label: Text(
                                        _isStartingDrive
                                            ? 'Starting...'
                                            : 'Start Drive',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue.shade700,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (isDriving)
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: ElevatedButton.icon(
                                      onPressed: _stopDriving,
                                      icon: const Icon(Icons.stop),
                                      label: const Text(
                                        'Stop Drive',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
      loading: () => Container(
        decoration: _bg(),
        child: const Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
      ),
      error: (e, st) => Container(
        decoration: _bg(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _glassCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 12),
                    Text('Error: $e'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DestinationPickerDialog extends StatefulWidget {
  final LatLng initialCenter;
  const _DestinationPickerDialog({required this.initialCenter});

  @override
  State<_DestinationPickerDialog> createState() => _DestinationPickerDialogState();
}

class _DestinationPickerDialogState extends State<_DestinationPickerDialog> {
  final MapController _ctrl = MapController();
  LatLng? _selected;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black54,
      body: Center(
        child: Container(
          width: screen.width * 0.95,
          height: screen.height * 0.82,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  color: Colors.blue.shade700,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.location_on, color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Set Destination',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(null),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _ctrl,
                      options: MapOptions(
                        initialCenter: widget.initialCenter,
                        initialZoom: 15,
                        onTap: (_, point) => setState(() => _selected = point),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.traces',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: widget.initialCenter,
                              width: 60,
                              height: 60,
                              child: const Icon(Icons.my_location, color: Colors.blue, size: 30),
                            ),
                            if (_selected != null)
                              Marker(
                                point: _selected!,
                                width: 60,
                                height: 60,
                                child: const Icon(Icons.location_on, color: Colors.red, size: 42),
                              ),
                          ],
                        ),
                      ],
                    ),
                    if (_selected != null)
                      Positioned(
                        top: 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.93),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 2)),
                              ],
                            ),
                            child: Text(
                              'Lat: ${_selected!.latitude.toStringAsFixed(5)},  Lng: ${_selected!.longitude.toStringAsFixed(5)}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.blueGrey),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(null),
                          child: const Text('Cancel'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: _selected == null ? null : () => Navigator.of(context).pop(_selected),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade700,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade300,
                          ),
                          child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}