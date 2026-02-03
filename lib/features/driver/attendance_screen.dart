import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../models/traces_user.dart';
import '../auth/auth_controller.dart';

class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider);

    if (user == null || user.assignedServiceId == null) {
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Attendance'),
            elevation: 2,
            bottom: const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.checklist), text: 'Today'),
                Tab(icon: Icon(Icons.history), text: 'Attendance History'),
              ],
            ),
          ),
          body: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning, size: 64, color: Colors.orange),
                SizedBox(height: 16),
                Text('No service assigned'),
              ],
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Student Attendance'),
          elevation: 2,
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.checklist), text: 'Today'),
              Tab(icon: Icon(Icons.history), text: 'Attendance History'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildTodayTab(context, user.assignedServiceId!),
            _AttendanceHistoryView(serviceId: user.assignedServiceId!),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayTab(BuildContext context, String serviceId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('assignedServiceId', isEqualTo: serviceId)
          .where('role', isEqualTo: 'passenger')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error: ${snapshot.error}'),
              ],
            ),
          );
        }

        final passengers = snapshot.data?.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return TracesUser(
                id: doc.id,
                name: data['name'] ?? 'Unknown',
                role: UserRole.passenger,
                assignedServiceId: data['assignedServiceId'],
                email: data['email'],
              );
            }).toList() ??
            [];

        if (passengers.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No passengers assigned',
                  style: TextStyle(fontSize: 16),
                ),
              ],
            ),
          );
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('services')
              .doc(serviceId)
              .collection('attendance')
              .snapshots(),
          builder: (context, attendanceSnapshot) {
            if (attendanceSnapshot.connectionState ==
                ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final attendanceDocs = attendanceSnapshot.data?.docs ?? [];
            final today = _startOfDay(DateTime.now());

            final Map<String, bool> todayAttendance = {};
            final Map<String, bool> isStudentMarked = {};

            for (final doc in attendanceDocs) {
              final data = doc.data() as Map<String, dynamic>;
              final passengerId = data['passengerId'] as String?;
              final ts = data['date'] as Timestamp?;
              final status = data['status'] as String?;
              final markedBy = data['markedBy'] as String?;

              if (passengerId == null || ts == null) continue;

              final date = ts.toDate();
              final dateStart = _startOfDay(date);

              if (dateStart.isAtSameMomentAs(today)) {
                final isPresent = status == 'present';
                todayAttendance[passengerId] = isPresent;
                isStudentMarked[passengerId] = markedBy == 'student';
              }
            }

            int presentCount = todayAttendance.values
                .where((isPresent) => isPresent)
                .length;
            int totalCount = passengers.length;

            return Column(
              children: [
                Container(
                  color: Colors.blue.shade50,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        'Today: ${DateFormat('MMMM dd, yyyy').format(DateTime.now())}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatCard(
                            'Total',
                            totalCount.toString(),
                            Icons.people,
                            Colors.blue,
                          ),
                          _buildStatCard(
                            'Present',
                            presentCount.toString(),
                            Icons.check_circle,
                            Colors.green,
                          ),
                          _buildStatCard(
                            'Absent',
                            (totalCount - presentCount).toString(),
                            Icons.cancel,
                            Colors.red,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: Colors.blue),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Students mark their own attendance. View-only for drivers.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: passengers.length,
                    itemBuilder: (context, index) {
                      final passenger = passengers[index];
                      final isPresent =
                          todayAttendance[passenger.id] ?? false;
                      final studentMarked =
                          isStudentMarked[passenger.id] ?? false;
                      final hasMarked = todayAttendance.containsKey(passenger.id);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          leading: CircleAvatar(
                            radius: 24,
                            backgroundColor: !hasMarked
                                ? Colors.grey
                                : isPresent
                                    ? Colors.green
                                    : Colors.red,
                            child: Text(
                              passenger.name.isNotEmpty
                                  ? passenger.name[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                            ),
                          ),
                          title: Text(
                            passenger.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                'Student ID: ${passenger.id.substring(0, 8)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (!hasMarked)
                                Row(
                                  children: [
                                    Icon(
                                      Icons.pending,
                                      size: 16,
                                      color: Colors.grey[600],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Not marked yet',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Row(
                                  children: [
                                    Icon(
                                      isPresent
                                          ? Icons.check_circle
                                          : Icons.cancel,
                                      size: 16,
                                      color: isPresent
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isPresent ? 'Present' : 'Absent',
                                      style: TextStyle(
                                        color: isPresent
                                            ? Colors.green
                                            : Colors.red,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (studentMarked) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                            color: Colors.blue.shade200,
                                          ),
                                        ),
                                        child: Text(
                                          'Self-marked',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.blue.shade700,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                            ],
                          ),
                          trailing: Icon(
                            Icons.visibility,
                            color: Colors.grey[400],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

class _AttendanceHistoryView extends StatefulWidget {
  final String serviceId;

  const _AttendanceHistoryView({required this.serviceId});

  @override
  State<_AttendanceHistoryView> createState() => _AttendanceHistoryViewState();
}

class _AttendanceHistoryViewState extends State<_AttendanceHistoryView> {
  DateTime _selectedDate = DateTime.now();

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _selectDate,
                  icon: const Icon(Icons.calendar_today),
                  label: Text(DateFormat('MMM dd, yyyy').format(_selectedDate)),
                ),
              ),
              const SizedBox(width: 8),
              if (_selectedDate.day != DateTime.now().day ||
                  _selectedDate.month != DateTime.now().month ||
                  _selectedDate.year != DateTime.now().year)
                IconButton(
                  icon: const Icon(Icons.today),
                  tooltip: 'Today',
                  onPressed: () {
                    setState(() {
                      _selectedDate = DateTime.now();
                    });
                  },
                ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<QuerySnapshot>(
            future: FirebaseFirestore.instance
                .collection('services')
                .doc(widget.serviceId)
                .collection('attendance')
                .where(
                  'date',
                  isGreaterThanOrEqualTo: DateTime(
                    _selectedDate.year,
                    _selectedDate.month,
                    _selectedDate.day,
                  ),
                )
                .where(
                  'date',
                  isLessThan: DateTime(
                    _selectedDate.year,
                    _selectedDate.month,
                    _selectedDate.day + 1,
                  ),
                )
                .get(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              final attendanceDocs = snapshot.data?.docs ?? [];

              if (attendanceDocs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.event_busy, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        'No attendance records for ${DateFormat('MMM dd').format(_selectedDate)}',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                );
              }

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .where('assignedServiceId', isEqualTo: widget.serviceId)
                    .where('role', isEqualTo: 'passenger')
                    .snapshots(),
                builder: (context, studentSnapshot) {
                  if (!studentSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final students = studentSnapshot.data!.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return TracesUser(
                      id: doc.id,
                      name: data['name'] ?? 'Unknown',
                      role: UserRole.passenger,
                      assignedServiceId: data['assignedServiceId'],
                      email: data['email'],
                    );
                  }).toList();

                  final attendanceMap = <String, Map<String, dynamic>>{};
                  for (final doc in attendanceDocs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final passengerId = data['passengerId'] as String?;
                    if (passengerId != null) {
                      attendanceMap[passengerId] = data;
                    }
                  }

                  int presentCount = attendanceMap.values
                      .where((data) => data['status'] == 'present')
                      .length;

                  return Column(
                    children: [
                      Container(
                        color: Colors.blue.shade50,
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatChip(
                              'Total',
                              attendanceMap.length.toString(),
                              Icons.people,
                              Colors.blue,
                            ),
                            _buildStatChip(
                              'Present',
                              presentCount.toString(),
                              Icons.check_circle,
                              Colors.green,
                            ),
                            _buildStatChip(
                              'Absent',
                              (attendanceMap.length - presentCount).toString(),
                              Icons.cancel,
                              Colors.red,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: attendanceMap.length,
                          itemBuilder: (context, index) {
                            final passengerId = attendanceMap.keys.elementAt(index);
                            final attendanceData = attendanceMap[passengerId]!;
                            final student = students.firstWhere(
                              (s) => s.id == passengerId,
                              orElse: () => TracesUser(
                                id: passengerId,
                                name: 'Unknown Student',
                                role: UserRole.passenger,
                                email: null,
                              ),
                            );

                            final isPresent = attendanceData['status'] == 'present';

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isPresent
                                      ? Colors.green
                                      : Colors.red,
                                  child: Text(
                                    student.name.isNotEmpty
                                        ? student.name[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                title: Text(
                                  student.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  'ID: ${student.id.substring(0, 8)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: Chip(
                                  label: Text(
                                    isPresent ? 'Present' : 'Absent',
                                    style: TextStyle(
                                      color: isPresent
                                          ? Colors.green
                                          : Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  backgroundColor: isPresent
                                      ? Colors.green.withValues(alpha: 0.1)
                                      : Colors.red.withValues(alpha: 0.1),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatChip(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}