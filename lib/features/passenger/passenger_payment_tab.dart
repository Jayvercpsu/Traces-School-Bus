import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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

class PassengerPaymentTab extends StatelessWidget {
  final String serviceId;
  final String passengerId;
  final String passengerName;

  const PassengerPaymentTab({
    super.key,
    required this.serviceId,
    required this.passengerId,
    required this.passengerName,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('services')
          .doc(serviceId)
          .collection('payments')
          .doc(passengerId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        bool isPaid = false;
        DateTime? dueDate;
        double amount = 0.0;
        String receiptReference = '';
        String paymentMethod = '';

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          isPaid = data['isPaid'] ?? false;
          amount = (data['amount'] ?? 0).toDouble();
          receiptReference = data['receiptReference'] ?? '';
          paymentMethod = data['paymentMethod'] ?? '';

          final dueDateTimestamp = data['dueDate'] as Timestamp?;
          if (dueDateTimestamp != null) {
            dueDate = dueDateTimestamp.toDate();
          }
        }

        final now = DateTime.now();
        String statusLabel = 'Not Set';
        Color statusColor = Colors.grey;
        IconData statusIcon = Icons.info_outline;

        if (isPaid) {
          statusLabel = 'Paid';
          statusColor = Colors.green;
          statusIcon = Icons.check_circle;
        } else if (dueDate != null) {
          final diff = dueDate.difference(now).inDays;
          if (diff < 0) {
            statusLabel = 'Overdue';
            statusColor = Colors.red;
            statusIcon = Icons.error;
          } else if (diff <= 7) {
            statusLabel = 'Due Soon';
            statusColor = Colors.orange;
            statusIcon = Icons.warning;
          } else {
            statusLabel = 'Upcoming';
            statusColor = Colors.blue;
            statusIcon = Icons.schedule;
          }
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: _glassCard(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                Row(
                  children: [
                    Icon(Icons.payments_rounded, color: Colors.blue.shade700, size: 28),
                    const SizedBox(width: 10),
                    const Text(
                      'Payment Status',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: statusColor.withValues(alpha: 0.30), width: 2),
                  ),
                  child: Column(
                    children: [
                      Icon(statusIcon, color: statusColor, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: statusColor,
                          fontSize: 24,
                        ),
                      ),
                      if (amount > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          '₱${amount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ],
                      if (dueDate != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Due: ${DateFormat('MMMM dd, yyyy').format(dueDate)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                      if (isPaid && receiptReference.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.receipt, color: Colors.green.shade700, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Ref: $receiptReference',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                Divider(color: Colors.grey.shade300),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Payment Information',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (dueDate == null && amount == 0) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.grey.shade700),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'No payment information set yet. Please contact your driver or admin for payment details.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.person_outline, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Student: $passengerName',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                        if (amount > 0) ...[
                          const SizedBox(height: 10),
                          Row(
                          children: [
                            const Icon(Icons.money, size: 18),
                            const SizedBox(width: 8),
                            Text(
                            'Amount: ₱${amount.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ],
                          ),
                        ],
                        if (dueDate != null) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Due Date: ${DateFormat('MMMM dd, yyyy').format(dueDate)}',
                                style: const TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              isPaid ? Icons.check_circle : Icons.cancel,
                              color: isPaid ? Colors.green : Colors.red,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Status: ${isPaid ? "Paid" : "Unpaid"}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isPaid ? Colors.green : Colors.red,
                              ),
                            ),
                          ],
                        ),
                        if (isPaid && paymentMethod.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(Icons.payment, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Payment Method: $paymentMethod',
                                style: const TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lightbulb_outline, color: Colors.blue.shade700, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Payment Instructions',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '• Pay via Cash or GCash to your driver\n'
                        '• Get a receipt reference number\n'
                        '• Driver will mark your payment as paid in the system\n'
                        '• Check this page to confirm payment status',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade800,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}