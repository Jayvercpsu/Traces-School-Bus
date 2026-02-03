import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../models/traces_user.dart';
import '../auth/auth_controller.dart';

class AssignedStudentsScreen extends ConsumerStatefulWidget {
  const AssignedStudentsScreen({super.key});

  @override
  ConsumerState<AssignedStudentsScreen> createState() =>
      _AssignedStudentsScreenState();
}

class _AssignedStudentsScreenState
    extends ConsumerState<AssignedStudentsScreen> {
  String _searchQuery = '';

  Future<void> _showSearchAndAssignDialog() async {
    final user = ref.read(authControllerProvider);
    if (user == null || user.assignedServiceId == null) return;

    await showDialog(
      context: context,
      builder: (context) =>
          _SearchStudentDialog(serviceId: user.assignedServiceId!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider);

    if (user == null || user.assignedServiceId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Assigned Students')),
        body: const Center(child: Text('No service assigned')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Assigned Students')),
      body: _buildStudentsTab(user.assignedServiceId!),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showSearchAndAssignDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Student'),
      ),
    );
  }

  Widget _buildStudentsTab(String serviceId) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search students...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value.toLowerCase();
              });
            },
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
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
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              final students =
                  snapshot.data?.docs.map((doc) {
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

              final filteredStudents = students.where((student) {
                return student.name.toLowerCase().contains(_searchQuery);
              }).toList();

              if (filteredStudents.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isEmpty
                            ? 'No students assigned'
                            : 'No students found',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: filteredStudents.length,
                itemBuilder: (context, index) {
                  final student = filteredStudents[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue,
                        child: Text(
                          student.name.isNotEmpty
                              ? student.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Text(
                        student.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('ID: ${student.id.substring(0, 8)}'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'remove') {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Remove Student'),
                                content: Text(
                                  'Remove ${student.name} from your service?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Remove'),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true) {
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(student.id)
                                  .update({'assignedServiceId': null});

                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('${student.name} removed'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            }
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'remove',
                            child: Row(
                              children: [
                                Icon(Icons.remove_circle, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Remove'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SearchStudentDialog extends ConsumerStatefulWidget {
  final String serviceId;

  const _SearchStudentDialog({required this.serviceId});

  @override
  ConsumerState<_SearchStudentDialog> createState() =>
      _SearchStudentDialogState();
}

class _SearchStudentDialogState extends ConsumerState<_SearchStudentDialog> {
  String _searchQuery = '';
  bool _isAssigning = false;

  Future<void> _assignStudent(TracesUser student) async {
    if (_isAssigning) return;
    setState(() => _isAssigning = true);

    try {
      final db = FirebaseFirestore.instance;
      final serviceRef = db.collection('services').doc(widget.serviceId);
      final userRef = db.collection('users').doc(student.id);

      await db.runTransaction((tx) async {
        final serviceSnap = await tx.get(serviceRef);

        final now = DateTime.now();
        final dueDate = Timestamp.fromDate(now.add(const Duration(days: 7)));

        if (!serviceSnap.exists) {
          tx.set(serviceRef, {
            'routeName': 'School Bus Route',
            'driverId': '',
            'driverName': '',
            'driverContact': '',
            'busPlateNumber': '',
            'busModel': '',
            'passengerIds': [student.id],
            'currentLocation': {'latitude': 0.0, 'longitude': 0.0},
            'eta': Timestamp.fromDate(now.add(const Duration(minutes: 15))),
            'status': 'preparing',
            'paymentDueDates': {student.id: dueDate},
          });
        } else {
          final data = serviceSnap.data() as Map<String, dynamic>;
          final passengerIds = List<String>.from(data['passengerIds'] ?? []);
          final paymentDueDates = Map<String, dynamic>.from(
            data['paymentDueDates'] ?? {},
          );

          if (!passengerIds.contains(student.id)) {
            passengerIds.add(student.id);
          }
          paymentDueDates[student.id] = paymentDueDates[student.id] ?? dueDate;

          tx.update(serviceRef, {
            'passengerIds': passengerIds,
            'paymentDueDates': paymentDueDates,
          });
        }

        tx.update(userRef, {'assignedServiceId': widget.serviceId});
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${student.name} added to your service'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to assign: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAssigning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Search & Add Students',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _isAssigning ? null : () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(
                hintText: 'Search by name...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .where('role', isEqualTo: 'passenger')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }

                  final allStudents =
                      snapshot.data?.docs.map((doc) {
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

                  final unassignedStudents = allStudents.where((student) {
                    final matchesSearch = student.name.toLowerCase().contains(
                      _searchQuery,
                    );
                    final isUnassigned =
                        student.assignedServiceId == null ||
                        student.assignedServiceId!.isEmpty;
                    return matchesSearch && isUnassigned;
                  }).toList();

                  if (unassignedStudents.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty
                                ? 'No unassigned students'
                                : 'No students found',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: unassignedStudents.length,
                    itemBuilder: (context, index) {
                      final student = unassignedStudents[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.grey,
                            child: Text(
                              student.name.isNotEmpty
                                  ? student.name[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(
                            student.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text('ID: ${student.id.substring(0, 8)}'),
                          trailing: ElevatedButton(
                            onPressed: _isAssigning
                                ? null
                                : () => _assignStudent(student),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                            child: _isAssigning
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Add'),
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
      ),
    );
  }
}
