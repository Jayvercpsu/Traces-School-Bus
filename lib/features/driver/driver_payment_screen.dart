import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../models/traces_user.dart';
import '../auth/auth_controller.dart';

class DriverPaymentScreen extends ConsumerStatefulWidget {
  const DriverPaymentScreen({super.key});

  @override
  ConsumerState<DriverPaymentScreen> createState() => _DriverPaymentScreenState();
}

class _DriverPaymentScreenState extends ConsumerState<DriverPaymentScreen> {
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider);

    if (user == null || user.assignedServiceId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Payment Management')),
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
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Management'),
        elevation: 2,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('assignedServiceId', isEqualTo: user.assignedServiceId)
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
          }).toList() ?? [];

          if (passengers.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No passengers assigned', style: TextStyle(fontSize: 16)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: passengers.length,
            itemBuilder: (context, index) {
              final passenger = passengers[index];
              return _PaymentCard(
                serviceId: user.assignedServiceId!,
                passenger: passenger,
              );
            },
          );
        },
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final String serviceId;
  final TracesUser passenger;

  const _PaymentCard({
    required this.serviceId,
    required this.passenger,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('services')
          .doc(serviceId)
          .collection('payments')
          .doc(passenger.id)
          .snapshots(),
      builder: (context, snapshot) {
        bool isPaid = false;
        DateTime? dueDate;
        double amount = 0.0;
        String receiptReference = '';
        String paymentMethod = 'Cash';

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          isPaid = data['isPaid'] ?? false;
          amount = (data['amount'] ?? 0).toDouble();
          receiptReference = data['receiptReference'] ?? '';
          paymentMethod = data['paymentMethod'] ?? 'Cash';

          final dueDateTimestamp = data['dueDate'] as Timestamp?;
          if (dueDateTimestamp != null) {
            dueDate = dueDateTimestamp.toDate();
          }
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: isPaid ? Colors.green : Colors.red,
              child: Text(
                passenger.name.isNotEmpty ? passenger.name[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
            title: Text(
              passenger.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      isPaid ? Icons.check_circle : Icons.cancel,
                      size: 16,
                      color: isPaid ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isPaid ? 'Paid' : 'Unpaid',
                      style: TextStyle(
                        color: isPaid ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (amount > 0) ...[
                  const SizedBox(height: 4),
                  Text('Amount: ₱${amount.toStringAsFixed(2)}'),
                ],
                if (dueDate != null) ...[
                  const SizedBox(height: 4),
                  Text('Due: ${DateFormat('MMM dd, yyyy').format(dueDate)}'),
                ],
                if (isPaid && paymentMethod.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Method: $paymentMethod'),
                ],
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _showPaymentDialog(context),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showPaymentDialog(BuildContext context) async {
    final db = FirebaseFirestore.instance;
    final paymentDoc = await db
        .collection('services')
        .doc(serviceId)
        .collection('payments')
        .doc(passenger.id)
        .get();

    bool isPaid = false;
    DateTime? dueDate;
    double amount = 0.0;
    String receiptReference = '';
    String paymentMethod = 'Cash';

    if (paymentDoc.exists) {
      final data = paymentDoc.data()!;
      isPaid = data['isPaid'] ?? false;
      amount = (data['amount'] ?? 0).toDouble();
      receiptReference = data['receiptReference'] ?? '';
      paymentMethod = data['paymentMethod'] ?? 'Cash';

      final dueDateTimestamp = data['dueDate'] as Timestamp?;
      if (dueDateTimestamp != null) {
        dueDate = dueDateTimestamp.toDate();
      }
    }

    if (!context.mounted) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _PaymentDialog(
        passengerName: passenger.name,
        initialIsPaid: isPaid,
        initialDueDate: dueDate,
        initialAmount: amount,
        initialReceiptReference: receiptReference,
        initialPaymentMethod: paymentMethod,
      ),
    );

    if (result != null) {
      await db
          .collection('services')
          .doc(serviceId)
          .collection('payments')
          .doc(passenger.id)
          .set({
        'passengerId': passenger.id,
        'passengerName': passenger.name,
        'isPaid': result['isPaid'],
        'amount': result['amount'],
        'dueDate': result['dueDate'] != null
            ? Timestamp.fromDate(result['dueDate'])
            : null,
        'receiptReference': result['receiptReference'],
        'paymentMethod': result['paymentMethod'],
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }
}

class _PaymentDialog extends StatefulWidget {
  final String passengerName;
  final bool initialIsPaid;
  final DateTime? initialDueDate;
  final double initialAmount;
  final String initialReceiptReference;
  final String initialPaymentMethod;

  const _PaymentDialog({
    required this.passengerName,
    required this.initialIsPaid,
    required this.initialDueDate,
    required this.initialAmount,
    required this.initialReceiptReference,
    required this.initialPaymentMethod,
  });

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late bool _isPaid;
  late DateTime? _dueDate;
  late TextEditingController _amountController;
  late TextEditingController _receiptController;
  late String _paymentMethod;

  @override
  void initState() {
    super.initState();
    _isPaid = widget.initialIsPaid;
    _dueDate = widget.initialDueDate;
    _paymentMethod = widget.initialPaymentMethod;
    _amountController = TextEditingController(
      text: widget.initialAmount > 0 ? widget.initialAmount.toStringAsFixed(2) : '',
    );
    _receiptController = TextEditingController(text: widget.initialReceiptReference);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _receiptController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Payment for ${widget.passengerName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Amount (₱)',
                prefixIcon: Icon(Icons.money),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: Text(_dueDate == null
                  ? 'Set Due Date'
                  : 'Due: ${DateFormat('MMMM dd, yyyy').format(_dueDate!)}'),
              trailing: const Icon(Icons.edit),
              onTap: _pickDate,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Payment Status'),
              subtitle: Text(_isPaid ? 'Paid' : 'Unpaid'),
              value: _isPaid,
              onChanged: (value) => setState(() => _isPaid = value),
              secondary: Icon(
                _isPaid ? Icons.check_circle : Icons.cancel,
                color: _isPaid ? Colors.green : Colors.red,
              ),
            ),
            if (_isPaid) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _paymentMethod,
                decoration: const InputDecoration(
                  labelText: 'Payment Method',
                  prefixIcon: Icon(Icons.payment),
                ),
                items: const [
                  DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'GCash', child: Text('GCash')),
                  DropdownMenuItem(value: 'Bank Transfer', child: Text('Bank Transfer')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _paymentMethod = value);
                  }
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _receiptController,
                decoration: const InputDecoration(
                  labelText: 'Receipt Reference (Optional)',
                  prefixIcon: Icon(Icons.receipt),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final amount = double.tryParse(_amountController.text) ?? 0.0;
            Navigator.of(context).pop({
              'isPaid': _isPaid,
              'amount': amount,
              'dueDate': _dueDate,
              'receiptReference': _receiptController.text.trim(),
              'paymentMethod': _paymentMethod,
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade700,
            foregroundColor: Colors.white,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}