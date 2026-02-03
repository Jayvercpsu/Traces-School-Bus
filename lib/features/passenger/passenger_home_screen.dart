import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../auth/auth_controller.dart';
import 'passenger_profile_screen.dart';
import 'passenger_controller.dart';
import 'passenger_payment_tab.dart';
import '../../models/school_service.dart';
import '../../models/attendance_record.dart';
import '../../services/route_service.dart';
import 'passenger_attendance_management_screen.dart';

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

Widget _glassCard({required Widget child, EdgeInsets? padding}) {
  return Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      color: Colors.white.withValues(alpha: 0.92),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.18),
          blurRadius: 20,
          spreadRadius: 2,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Padding(padding: padding ?? const EdgeInsets.all(16), child: child),
  );
}

class PassengerHomeScreen extends ConsumerStatefulWidget {
  const PassengerHomeScreen({super.key});

  @override
  ConsumerState<PassengerHomeScreen> createState() =>
      _PassengerHomeScreenState();
}

class _PassengerHomeScreenState extends ConsumerState<PassengerHomeScreen> {
  final MapController _mapController = MapController();
  int _tabIndex = 0;

  String _title() {
    if (_tabIndex == 1) return 'My Attendance';
    if (_tabIndex == 2) return 'Payment';
    return 'Passenger';
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
      if (context.mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    }
  }

  AppBar _appBar(BuildContext context) {
    return AppBar(
      title: Text(_title()),
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: Colors.white,
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.person, color: Colors.white),
          onSelected: (value) async {
            if (value == 'profile') {
              if (!context.mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PassengerProfileScreen(),
                ),
              );
            } else if (value == 'logout') {
              await _confirmLogout(context);
            }
          },
          itemBuilder: (BuildContext context) => [
            const PopupMenuItem<String>(
              value: 'profile',
              child: Row(
                children: [
                  Icon(Icons.person_outline),
                  SizedBox(width: 12),
                  Text('Profile'),
                ],
              ),
            ),
            const PopupMenuItem<String>(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final serviceStream = ref.watch(passengerServiceStreamProvider);
    final user = ref.watch(authControllerProvider);

    return serviceStream.when(
      data: (service) {
        return Container(
          decoration: _bg(),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            extendBodyBehindAppBar: true,
            appBar: _appBar(context),
            body: SafeArea(
              child: Builder(
                builder: (context) {
                  if (user == null) {
                    return Center(
                      child: _glassCard(
                        child: const Text(
                          'User not logged in',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    );
                  }

                  if (service == null) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: _glassCard(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.blue.shade50,
                                ),
                                child: Icon(
                                  Icons.directions_bus_outlined,
                                  size: 52,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No Driver Assigned',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade900,
                                    ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'You are not assigned to any driver yet.\nPlease wait for a driver to add you to their service.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.blue.shade100,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: Colors.blue.shade700,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Once assigned, you will see the bus location and schedule here.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.blue.shade700,
                                          fontWeight: FontWeight.w600,
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

                  final pages = <Widget>[
                    _PassengerHomeTab(
                      mapController: _mapController,
                      service: service,
                      userId: user.id,
                    ),
                    _PassengerAttendanceTab(
                      serviceId: service.id,
                      passengerId: user.id,
                    ),
                    PassengerPaymentTab(
                      serviceId: service.id,
                      passengerId: user.id,
                      passengerName: user.name,
                    ),
                  ];

                  return IndexedStack(index: _tabIndex, children: pages);
                },
              ),
            ),
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: _tabIndex,
              onTap: (i) => setState(() => _tabIndex = i),
              type: BottomNavigationBarType.fixed,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.checklist_rounded),
                  label: 'My Attendance',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.payments_rounded),
                  label: 'Payment',
                ),
              ],
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
                child: Text(
                  'Error: $e',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PassengerHomeTab extends StatefulWidget {
  final MapController mapController;
  final SchoolService service;
  final String userId;

  const _PassengerHomeTab({
    required this.mapController,
    required this.service,
    required this.userId,
  });

  @override
  State<_PassengerHomeTab> createState() => _PassengerHomeTabState();
}

class _PassengerHomeTabState extends State<_PassengerHomeTab>
    with SingleTickerProviderStateMixin {
  bool _mapReady = false;
  bool _expanded = false;

  AnimationController? _camAnim;

  @override
  void initState() {
    super.initState();
    _camAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
  }

  @override
  void dispose() {
    _camAnim?.dispose();
    super.dispose();
  }

  void _safeMove(LatLng center, double zoom) {
    if (!_mapReady) return;
    widget.mapController.move(center, zoom);
  }

  void _safeAnimatedMove(LatLng to, double zoom) {
    if (!_mapReady) return;
    if (_camAnim == null) return;

    final fromCenter = widget.mapController.camera.center;
    final fromZoom = widget.mapController.camera.zoom;

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
      widget.mapController.move(c, z);
    }

    _camAnim!.addListener(tick);
    _camAnim!.addStatusListener((s) {
      if (s == AnimationStatus.completed || s == AnimationStatus.dismissed) {
        _camAnim!.removeListener(tick);
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

  Future<void> _fitRouteAnimated(List<LatLng> route) async {
    if (!_mapReady) return;
    if (route.isEmpty) return;
    final center = _routeCenter(route);
    if (center == null) return;
    _safeAnimatedMove(center, 13.8);
    await Future.delayed(const Duration(milliseconds: 520));
  }

  @override
  Widget build(BuildContext context) {
    final mapCenter = LatLng(
      widget.service.currentLocation.latitude,
      widget.service.currentLocation.longitude,
    );

    LatLng? destinationLatLng;
    if (widget.service.status == ServiceStatus.onTheWay &&
        widget.service.destinationLocation != null) {
      destinationLatLng = LatLng(
        widget.service.destinationLocation!.latitude,
        widget.service.destinationLocation!.longitude,
      );
    }

    final routeFuture = destinationLatLng != null
        ? RouteService.getRoute(mapCenter, destinationLatLng)
        : Future.value(<LatLng>[]);

    Widget buildPaymentInfo() {
      return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('services')
            .doc(widget.service.id)
            .collection('payments')
            .doc(widget.userId)
            .snapshots(),
        builder: (context, snapshot) {
          String dueLabel = 'No due date';
          Color dueColor = Colors.grey;

          if (snapshot.hasData && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>;
            final dueDateTimestamp = data['dueDate'] as Timestamp?;

            if (dueDateTimestamp != null) {
              final dueDate = dueDateTimestamp.toDate();
              final now = DateTime.now();
              final diff = dueDate.difference(now).inDays;
              final formatted = DateFormat.yMMMd().format(dueDate);

              if (diff < 0) {
                dueLabel = 'Overdue ($formatted)';
                dueColor = Colors.red;
              } else if (diff <= 7) {
                dueLabel = 'Due soon ($formatted)';
                dueColor = Colors.orange;
              } else {
                dueLabel = 'Due on $formatted';
                dueColor = Colors.green;
              }
            }
          }

          return Row(
            children: [
              const Icon(Icons.payments_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  dueLabel,
                  style: TextStyle(
                    color: dueColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          );
        },
      );
    }

    final statusText = switch (widget.service.status) {
      ServiceStatus.preparing => 'Preparing',
      ServiceStatus.onTheWay => 'On the way',
      ServiceStatus.arrived => 'Arrived',
      ServiceStatus.completed => 'Completed',
    };

    String arrivalHint = '';
    if (widget.service.status == ServiceStatus.onTheWay) {
      final diffMinutes = widget.service.eta
          .difference(DateTime.now())
          .inMinutes;
      if (diffMinutes <= 0) {
        arrivalHint = 'Bus should be arriving now.';
      } else if (diffMinutes <= 5) {
        arrivalHint = 'School bus will arrive soon.';
      } else {
        arrivalHint = 'Bus is on the way to your stop.';
      }
    } else if (widget.service.status == ServiceStatus.arrived) {
      arrivalHint = 'School bus has arrived at your stop.';
    }

    final collapsedMapHeight = MediaQuery.of(context).size.height * 0.42;

    Widget mapSection({required bool expanded}) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: expanded ? 0 : 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(expanded ? 0 : 20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOut,
            height: expanded ? null : collapsedMapHeight,
            constraints: expanded ? const BoxConstraints.expand() : null,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
            ),
            child: FutureBuilder<List<LatLng>>(
              future: routeFuture,
              builder: (context, snapshot) {
                final polylinePoints = snapshot.data ?? <LatLng>[];

                return Stack(
                  children: [
                    FlutterMap(
                      mapController: widget.mapController,
                      options: MapOptions(
                        initialCenter: mapCenter,
                        initialZoom: 14,
                        onMapReady: () {
                          if (_mapReady) return;
                          _mapReady = true;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _safeAnimatedMove(mapCenter, 15.5);
                          });
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.traces',
                        ),
                        if (polylinePoints.isNotEmpty)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: polylinePoints,
                                strokeWidth: 4,
                                color: Colors.blue,
                              ),
                            ],
                          ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: mapCenter,
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
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blueAccent,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text(
                                      'Bus',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (destinationLatLng != null)
                              Marker(
                                point: destinationLatLng,
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
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Text(
                                        'Destination',
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
                              icon: const Icon(Icons.route, color: Colors.blue),
                              tooltip: 'Route view',
                              onPressed: () =>
                                  _fitRouteAnimated(polylinePoints),
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
                              tooltip: 'Center to bus location',
                              onPressed: () => _safeAnimatedMove(mapCenter, 16),
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
                            expanded ? Icons.fullscreen_exit : Icons.fullscreen,
                            color: Colors.blue,
                          ),
                          tooltip: expanded
                              ? 'Exit full screen'
                              : 'Full screen',
                          onPressed: () =>
                              setState(() => _expanded = !_expanded),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        if (!_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _glassCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.location_on, color: Colors.blue.shade700),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Live Bus Tracking',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          arrivalHint.isNotEmpty
                              ? arrivalHint
                              : 'Tracking active when driver is moving.',
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
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.blue.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_expanded) Expanded(child: mapSection(expanded: true)),
        if (!_expanded) mapSection(expanded: false),
        const SizedBox(height: 12),
        if (!_expanded)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _glassCard(
                padding: const EdgeInsets.all(16),
                child: ListView(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.timer_outlined, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'ETA: ${DateFormat('h:mm a').format(widget.service.eta)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Image.asset('assets/images/school_bus.png', width: 66),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Bus: ${widget.service.busModel} (${widget.service.busPlateNumber})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text('Driver: ${widget.service.driverName}'),
                              const SizedBox(height: 4),
                              Text('Contact: ${widget.service.driverContact}'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    buildPaymentInfo(),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PassengerAttendanceTab extends StatelessWidget {
  final String serviceId;
  final String passengerId;

  const _PassengerAttendanceTab({
    required this.serviceId,
    required this.passengerId,
  });

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final todayStart = _startOfDay(DateTime.now());
    final tomorrowStart = todayStart.add(const Duration(days: 1));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: _glassCard(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Today',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PassengerAttendanceManagementScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit_calendar, size: 16),
                  label: const Text('Manage Absence'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ✅ single source of truth (stream) para walay flicker
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('services')
                  .doc(serviceId)
                  .collection('attendance')
                  .where('passengerId', isEqualTo: passengerId)
                  .limit(200)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Colors.red.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Failed to load attendance: ${snapshot.error}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];

                // Map docs -> (date, status), sort desc by date
                final raw = docs.map((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final ts = data['date'];
                  DateTime date = DateTime.now();
                  if (ts is Timestamp) date = ts.toDate();

                  final status = (data['status'] ?? '').toString();
                  final isPresent = status == 'present';

                  return {
                    'date': date,
                    'day': _startOfDay(date),
                    'isPresent': isPresent,
                  };
                }).toList();

                raw.sort(
                  (a, b) =>
                      (b['date'] as DateTime).compareTo(a['date'] as DateTime),
                );

                // ✅ Keep only 1 record per day (latest record for that day)
                final Map<DateTime, Map<String, dynamic>> byDay = {};
                for (final r in raw) {
                  final day = r['day'] as DateTime;
                  byDay.putIfAbsent(day, () => r);
                }

                // ✅ TODAY status
                final todayRecord = byDay[todayStart];
                AttendanceStatus? todayStatus;
                String? todayAttendanceDocId;
                
                if (todayRecord != null) {
                  todayStatus = (todayRecord['isPresent'] as bool)
                      ? AttendanceStatus.present
                      : AttendanceStatus.absent;
                  
                  for (final doc in docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final ts = data['date'];
                    if (ts is Timestamp) {
                      final date = ts.toDate();
                      final day = _startOfDay(date);
                      if (day == todayStart) {
                        todayAttendanceDocId = doc.id;
                        break;
                      }
                    }
                  }
                }

                Widget todayWidget;
                final canMarkToday = todayStatus == null;
                
                if (todayStatus == null) {
                  todayWidget = Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200, width: 2),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.pending_actions,
                          color: Colors.blue.shade700,
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Mark Your Attendance',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Please mark yourself as Present or Absent for today',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  );
                } else {
                  final isPresent = todayStatus == AttendanceStatus.present;
                  todayWidget = Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isPresent
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isPresent
                            ? Colors.green.shade200
                            : Colors.red.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isPresent ? Icons.check_circle : Icons.cancel,
                          color: isPresent ? Colors.green : Colors.red,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isPresent
                                    ? 'Attendance: Present ✓'
                                    : 'Attendance: Absent',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isPresent
                                      ? Colors.green.shade800
                                      : Colors.red.shade800,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                DateFormat('MMMM dd, yyyy').format(DateTime.now()),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          color: Colors.blue.shade700,
                          tooltip: 'Edit attendance',
                          onPressed: () async {
                            final newStatus = await showDialog<String>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Edit Today\'s Attendance'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Current status: ${isPresent ? "Present" : "Absent"}',
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text('Change to:'),
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () => Navigator.pop(context, 'present'),
                                    icon: const Icon(Icons.check_circle, size: 18),
                                    label: const Text('Present'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () => Navigator.pop(context, 'absent'),
                                    icon: const Icon(Icons.cancel, size: 18),
                                    label: const Text('Absent'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            );

                            if (newStatus == null || todayAttendanceDocId == null) return;

                            try {
                              await FirebaseFirestore.instance
                                  .collection('services')
                                  .doc(serviceId)
                                  .collection('attendance')
                                  .doc(todayAttendanceDocId)
                                  .update({
                                'status': newStatus,
                                'updatedAt': FieldValue.serverTimestamp(),
                              });

                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '✓ Attendance updated to ${newStatus == "present" ? "Present" : "Absent"}',
                                    ),
                                    backgroundColor: newStatus == 'present' 
                                        ? Colors.green 
                                        : Colors.orange,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error updating: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  );
                } 

                // ✅ RECENT records (exclude today)
                final recentDays =
                    byDay.keys.where((d) => d.isBefore(todayStart)).toList()
                      ..sort((a, b) => b.compareTo(a));

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    todayWidget,
                    if (canMarkToday) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Mark Present'),
                                    content: const Text(
                                      'Mark yourself as PRESENT for today?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, false),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(context, true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('Confirm'),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm != true) return;

                                try {
                                  final startOfDay = DateTime(
                                    DateTime.now().year,
                                    DateTime.now().month,
                                    DateTime.now().day,
                                  );
                                  
                                  await FirebaseFirestore.instance
                                      .collection('services')
                                      .doc(serviceId)
                                      .collection('attendance')
                                      .add({
                                    'passengerId': passengerId,
                                    'date': Timestamp.fromDate(startOfDay),
                                    'status': 'present',
                                    'markedBy': 'student',
                                    'createdAt': FieldValue.serverTimestamp(),
                                  });
                                  
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('✓ Marked as Present for today'),
                                        backgroundColor: Colors.green,
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Error: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.check_circle),
                              label: const Text('Present'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Mark Absent'),
                                    content: const Text(
                                      'Mark yourself as ABSENT for today?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, false),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(context, true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('Confirm'),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm != true) return;

                                try {
                                  final startOfDay = DateTime(
                                    DateTime.now().year,
                                    DateTime.now().month,
                                    DateTime.now().day,
                                  );
                                  
                                  await FirebaseFirestore.instance
                                      .collection('services')
                                      .doc(serviceId)
                                      .collection('attendance')
                                      .add({
                                    'passengerId': passengerId,
                                    'date': Timestamp.fromDate(startOfDay),
                                    'status': 'absent',
                                    'markedBy': 'student',
                                    'createdAt': FieldValue.serverTimestamp(),
                                  });
                                  
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Marked as Absent for today'),
                                        backgroundColor: Colors.orange,
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Error: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.cancel),
                              label: const Text('Absent'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 16,
                              color: Colors.blue.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'You can edit your attendance for today only',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blue.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Divider(color: Colors.grey.shade300),
                    const SizedBox(height: 10),
                    const Text(
                      'Recent Records',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),

                    if (recentDays.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.grey.shade700,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'No previous attendance records found',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    if (recentDays.isNotEmpty)
                      Column(
                        children: recentDays.take(30).map((day) {
                          final r = byDay[day]!;
                          final isPresent = r['isPresent'] as bool;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isPresent ? Icons.check_circle : Icons.cancel,
                                  color: isPresent ? Colors.green : Colors.red,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    DateFormat('MMMM dd, yyyy').format(day),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        (isPresent ? Colors.green : Colors.red)
                                            .withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color:
                                          (isPresent
                                                  ? Colors.green
                                                  : Colors.red)
                                              .withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: Text(
                                    isPresent ? 'Present' : 'Absent',
                                    style: TextStyle(
                                      color: isPresent
                                          ? Colors.green.shade800
                                          : Colors.red.shade800,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
