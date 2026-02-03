import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../auth/auth_controller.dart';

class PassengerAttendanceManagementScreen extends ConsumerStatefulWidget {
  const PassengerAttendanceManagementScreen({super.key});

  @override
  ConsumerState<PassengerAttendanceManagementScreen> createState() =>
      _PassengerAttendanceManagementScreenState();
}

class _PassengerAttendanceManagementScreenState
    extends ConsumerState<PassengerAttendanceManagementScreen> {
  DateTime? _selectedDate;

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _markAsAbsent(String serviceId, String passengerId) async {
    if (_selectedDate == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a date first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Absence'),
        content: Text(
          'Mark yourself as absent on ${DateFormat('MMMM dd, yyyy').format(_selectedDate!)}?',
        ),
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
            child: const Text('Mark Absent'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      final startOfDay = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
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

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Marked as absent on ${DateFormat('MMM dd, yyyy').format(_selectedDate!)}',
          ),
          backgroundColor: Colors.green,
        ),
      );

      setState(() => _selectedDate = null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _cancelAbsence(
    String serviceId,
    String passengerId,
    String docId,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Absence'),
        content: const Text('Remove this absence mark?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await FirebaseFirestore.instance
          .collection('services')
          .doc(serviceId)
          .collection('attendance')
          .doc(docId)
          .delete();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Absence cancelled'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider);

    if (user == null || user.assignedServiceId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Manage Attendance')),
        body: const Center(
          child: Text('No service assigned'),
        ),
      );
    }

    final serviceId = user.assignedServiceId!;
    final passengerId = user.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage My Attendance'),
        elevation: 2,
      ),
      body: Column(
        children: [
          Container(
            color: Colors.blue.shade50,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mark Future Absence',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Select a future date when you will be absent',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _selectDate,
                        icon: const Icon(Icons.calendar_today),
                        label: Text(
                          _selectedDate == null
                              ? 'Select Date'
                              : DateFormat('MMMM dd, yyyy')
                                  .format(_selectedDate!),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () => _markAsAbsent(serviceId, passengerId),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Mark Absent'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Scheduled Absences (Student-Marked)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('services')
                  .doc(serviceId)
                  .collection('attendance')
                  .where('passengerId', isEqualTo: passengerId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}'),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);

                final futureDocs = docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final status = data['status'] as String?;
                  final markedBy = data['markedBy'] as String?;
                  final ts = data['date'] as Timestamp?;
                  
                  if (status != 'absent' || markedBy != 'student' || ts == null) {
                    return false;
                  }
                  
                  final date = ts.toDate();
                  final dayStart = DateTime(date.year, date.month, date.day);
                  return dayStart.isAfter(today) ||
                      dayStart.isAtSameMomentAs(today);
                }).toList();

                futureDocs.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final aDate = (aData['date'] as Timestamp).toDate();
                  final bDate = (bData['date'] as Timestamp).toDate();
                  return aDate.compareTo(bDate);
                });

                if (futureDocs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.event_available,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No scheduled absences',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Mark future dates when you will be absent',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: futureDocs.length,
                  itemBuilder: (context, index) {
                    final doc = futureDocs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final ts = data['date'] as Timestamp;
                    final date = ts.toDate();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.red.shade100,
                          child: Icon(
                            Icons.event_busy,
                            color: Colors.red.shade700,
                          ),
                        ),
                        title: Text(
                          DateFormat('EEEE, MMMM dd, yyyy').format(date),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text('Marked as Absent'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _cancelAbsence(
                            serviceId,
                            passengerId,
                            doc.id,
                          ),
                          tooltip: 'Cancel this absence',
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}