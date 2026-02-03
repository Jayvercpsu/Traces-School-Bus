import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class EmailService {
  static const String _publicKey = "319057b52fb24a70056b67b81621cc96";
  static const String _privateKey = "fac4af48e2a18b05e1dd178e7cacd48e";
  static const String _fromEmail = "jayjayzjpa@gmail.com";
  static const String _fromName = "TRACES School Bus";

  static Future<bool> _sendEmail({
    required String toEmail,
    required String toName,
    required String subject,
    required String textPart,
    required String htmlPart,
  }) async {
    try {
      final response = await http.post(
        Uri.parse("https://api.mailjet.com/v3.1/send"),
        headers: {
          "Content-Type": "application/json",
          "Authorization":
              "Basic ${base64Encode(utf8.encode("$_publicKey:$_privateKey"))}",
        },
        body: jsonEncode({
          "Messages": [
            {
              "From": {"Email": _fromEmail, "Name": _fromName},
              "To": [
                {"Email": toEmail, "Name": toName},
              ],
              "Subject": subject,
              "TextPart": textPart,
              "HTMLPart": htmlPart,
            },
          ],
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error sending email: $e');
      return false;
    }
  }

  static Future<void> sendBusOnTheWayNotifications(String serviceId) async {
    try {
      final serviceDoc = await FirebaseFirestore.instance
          .collection('services')
          .doc(serviceId)
          .get();

      if (!serviceDoc.exists) return;

      final serviceData = serviceDoc.data()!;
      final busModel = serviceData['busModel'] ?? 'School Bus';
      final busPlateNumber = serviceData['busPlateNumber'] ?? '';
      final driverName = serviceData['driverName'] ?? 'Driver';
      final etaTimestamp = serviceData['eta'] as Timestamp?;
      final etaTime = etaTimestamp != null
          ? DateFormat('h:mm a').format(etaTimestamp.toDate())
          : 'Soon';

      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('assignedServiceId', isEqualTo: serviceId)
          .where('role', isEqualTo: 'passenger')
          .get();

      for (var userDoc in usersSnapshot.docs) {
        final userData = userDoc.data();
        final email = userData['email'] as String?;
        final name = userData['name'] ?? 'Student';

        if (email != null && email.isNotEmpty) {
          await _sendEmail(
            toEmail: email,
            toName: name,
            subject: 'School Bus is On The Way! 🚌',
            textPart:
                '''
Hello $name,

Your school bus is now on the way!

Bus: $busModel ($busPlateNumber)
Driver: $driverName
Estimated Arrival: $etaTime

Please be ready at your pickup point.

- TRACES School Bus System
            ''',
            htmlPart:
                '''
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
    .content { background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px; }
    .bus-icon { font-size: 48px; margin-bottom: 10px; }
    .info-box { background: white; padding: 20px; border-radius: 8px; margin: 20px 0; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
    .info-row { margin: 10px 0; }
    .label { font-weight: bold; color: #667eea; }
    .button { display: inline-block; background: #667eea; color: white; padding: 12px 30px; text-decoration: none; border-radius: 5px; margin-top: 20px; }
    .footer { text-align: center; margin-top: 20px; color: #666; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="bus-icon">🚌</div>
      <h1>Your Bus is On The Way!</h1>
    </div>
    <div class="content">
      <p>Hello <strong>$name</strong>,</p>
      <p>Good news! Your school bus is now on the way to your pickup point.</p>
      
      <div class="info-box">
        <div class="info-row">
          <span class="label">🚍 Bus:</span> $busModel ($busPlateNumber)
        </div>
        <div class="info-row">
          <span class="label">👨‍✈️ Driver:</span> $driverName
        </div>
        <div class="info-row">
          <span class="label">⏰ Estimated Arrival:</span> $etaTime
        </div>
      </div>
      
      <p><strong>Please be ready at your pickup point!</strong></p>
      
      <div class="footer">
        <p>TRACES - School Bus Tracking System</p>
        <p>This is an automated notification. Please do not reply to this email.</p>
      </div>
    </div>
  </div>
</body>
</html>
            ''',
          );

          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    } catch (e) {
      print('Error sending bus on-the-way notifications: $e');
    }
  }

  static Future<void> sendBusArrivingSoonNotifications(String serviceId) async {
    try {
      final serviceDoc = await FirebaseFirestore.instance
          .collection('services')
          .doc(serviceId)
          .get();

      if (!serviceDoc.exists) return;

      final serviceData = serviceDoc.data()!;
      final busModel = serviceData['busModel'] ?? 'School Bus';
      final busPlateNumber = serviceData['busPlateNumber'] ?? '';
      final driverName = serviceData['driverName'] ?? 'Driver';

      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('assignedServiceId', isEqualTo: serviceId)
          .where('role', isEqualTo: 'passenger')
          .get();

      for (var userDoc in usersSnapshot.docs) {
        final userData = userDoc.data();
        final email = userData['email'] as String?;
        final name = userData['name'] ?? 'Student';

        if (email != null && email.isNotEmpty) {
          await _sendEmail(
            toEmail: email,
            toName: name,
            subject: 'School Bus Arriving Soon! ⚠️',
            textPart:
                '''
Hello $name,

URGENT: Your school bus is arriving soon!

Hapit na maabot ang school bus!

Bus: $busModel ($busPlateNumber)
Driver: $driverName
Expected Arrival: Within 5 minutes

Please be at your pickup point NOW!

- TRACES School Bus System
            ''',
            htmlPart:
                '''
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
    .content { background: #fff5f5; padding: 30px; border-radius: 0 0 10px 10px; }
    .urgent-icon { font-size: 48px; margin-bottom: 10px; animation: pulse 1.5s infinite; }
    @keyframes pulse { 0%, 100% { transform: scale(1); } 50% { transform: scale(1.1); } }
    .info-box { background: white; padding: 20px; border-radius: 8px; margin: 20px 0; border-left: 4px solid #f5576c; }
    .info-row { margin: 10px 0; }
    .label { font-weight: bold; color: #f5576c; }
    .warning { background: #fff3cd; border: 2px solid #ffc107; padding: 15px; border-radius: 8px; margin: 20px 0; text-align: center; font-weight: bold; color: #856404; }
    .footer { text-align: center; margin-top: 20px; color: #666; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="urgent-icon">⚠️</div>
      <h1>Bus Arriving Soon!</h1>
    </div>
    <div class="content">
      <p>Hello <strong>$name</strong>,</p>
      
      <div class="warning">
        ⏰ HAPIT NA MAABOT ANG SCHOOL BUS! ⏰
      </div>
      
      <p>Your school bus will arrive at your pickup point within the next <strong>5 minutes</strong>!</p>
      
      <div class="info-box">
        <div class="info-row">
          <span class="label">🚍 Bus:</span> $busModel ($busPlateNumber)
        </div>
        <div class="info-row">
          <span class="label">👨‍✈️ Driver:</span> $driverName
        </div>
        <div class="info-row">
          <span class="label">⏰ Arrival:</span> Within 5 minutes
        </div>
      </div>
      
      <p style="text-align: center; font-size: 18px; color: #f5576c; font-weight: bold;">
        📍 Please be at your pickup point NOW! 📍
      </p>
      
      <div class="footer">
        <p>TRACES - School Bus Tracking System</p>
        <p>This is an automated notification. Please do not reply to this email.</p>
      </div>
    </div>
  </div>
</body>
</html>
            ''',
          );

          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    } catch (e) {
      print('Error sending arriving-soon notifications: $e');
    }
  }

  static Future<void> sendPaymentReminderNotifications(String serviceId) async {
    try {
      final serviceDoc = await FirebaseFirestore.instance
          .collection('services')
          .doc(serviceId)
          .get();

      if (!serviceDoc.exists) return;

      final now = DateTime.now();
      final paymentsSnapshot = await FirebaseFirestore.instance
          .collection('services')
          .doc(serviceId)
          .collection('payments')
          .get();

      for (var paymentDoc in paymentsSnapshot.docs) {
        final paymentData = paymentDoc.data();
        final userId = paymentDoc.id;
        final isPaid = paymentData['isPaid'] ?? false;

        if (isPaid) continue;

        final dueDateTimestamp = paymentData['dueDate'] as Timestamp?;
        if (dueDateTimestamp == null) continue;

        final dueDate = dueDateTimestamp.toDate();
        final daysUntilDue = dueDate.difference(now).inDays;

        if (daysUntilDue == 7 || daysUntilDue == 3) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .get();

          if (!userDoc.exists) continue;

          final userData = userDoc.data()!;
          final email = userData['email'] as String?;
          final name = userData['name'] ?? 'Student';

          if (email == null || email.isEmpty) continue;

          final amount = (paymentData['amount'] ?? 0).toDouble();
          final paymentMethod = paymentData['paymentMethod'] ?? 'Cash or GCash';
          final dueDateFormatted = DateFormat('MMMM dd, yyyy').format(dueDate);

          String urgencyLevel = daysUntilDue == 3 ? 'URGENT' : 'Important';
          String urgencyColor = daysUntilDue == 3 ? '#dc3545' : '#ffc107';
          String urgencyIcon = daysUntilDue == 3 ? '⚠️' : '⏰';

          await _sendEmail(
            toEmail: email,
            toName: name,
            subject:
                '$urgencyLevel: Payment Due in $daysUntilDue Days - School Bus Service 💰',
            textPart:
                '''
Hello $name,

$urgencyLevel REMINDER: Your school bus service payment is due in $daysUntilDue day(s)!

Payment Details:
Amount: ₱${amount.toStringAsFixed(2)}
Due Date: $dueDateFormatted
Days Remaining: $daysUntilDue day(s)
Payment Method: $paymentMethod

Please ensure payment is made before the due date to avoid service interruption.

You can pay via:
- Cash to your driver
- GCash to your driver
- Bank transfer (contact driver for details)

After payment, please get a receipt reference number from your driver.

Thank you for using TRACES School Bus Service!

- TRACES School Bus System
            ''',
            htmlPart:
                '''
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: linear-gradient(135deg, $urgencyColor 0%, #fd7e14 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
    .content { background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px; }
    .money-icon { font-size: 48px; margin-bottom: 10px; }
    .urgency-badge { background: white; color: $urgencyColor; padding: 8px 16px; border-radius: 20px; font-weight: bold; display: inline-block; margin-top: 10px; }
    .info-box { background: white; padding: 20px; border-radius: 8px; margin: 20px 0; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
    .info-row { margin: 12px 0; font-size: 16px; }
    .label { font-weight: bold; color: #667eea; display: inline-block; min-width: 140px; }
    .value { color: #333; }
    .amount { font-size: 24px; font-weight: bold; color: #28a745; text-align: center; margin: 20px 0; }
    .due-date { background: #fff3cd; border-left: 4px solid $urgencyColor; padding: 15px; margin: 20px 0; border-radius: 4px; }
    .payment-methods { background: #e7f3ff; padding: 20px; border-radius: 8px; margin: 20px 0; }
    .payment-methods ul { margin: 10px 0; padding-left: 20px; }
    .payment-methods li { margin: 8px 0; }
    .footer { text-align: center; margin-top: 20px; color: #666; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="money-icon">$urgencyIcon💰</div>
      <h1>Payment Reminder</h1>
      <div class="urgency-badge">$urgencyLevel - $daysUntilDue Days Left</div>
    </div>
    <div class="content">
      <p>Hello <strong>$name</strong>,</p>
      <p>This is ${daysUntilDue == 3 ? 'an <strong>URGENT</strong>' : 'an important'} reminder that your school bus service payment is due soon.</p>
      
      <div class="due-date">
        <div class="info-row">
          <span class="label">📅 Due Date:</span>
          <span class="value">$dueDateFormatted</span>
        </div>
        <div class="info-row">
          <span class="label">⏳ Days Remaining:</span>
          <span class="value" style="color: $urgencyColor; font-weight: bold;">$daysUntilDue day(s)</span>
        </div>
      </div>
      
      <div class="amount">₱${amount.toStringAsFixed(2)}</div>
      
      <div class="info-box">
        <div class="info-row">
          <span class="label">💳 Payment Method:</span>
          <span class="value">$paymentMethod</span>
        </div>
        <div class="info-row">
          <span class="label">📋 Status:</span>
          <span class="value" style="color: #dc3545; font-weight: bold;">Unpaid</span>
        </div>
      </div>
      
      <div class="payment-methods">
        <p><strong>💵 How to Pay:</strong></p>
        <ul>
          <li><strong>Cash:</strong> Pay directly to your driver</li>
          <li><strong>GCash:</strong> Transfer to your driver's GCash number</li>
          <li><strong>Bank Transfer:</strong> Contact your driver for bank details</li>
        </ul>
        <p style="margin-top: 15px;"><strong>Important:</strong> After payment, please get a receipt reference number from your driver for verification.</p>
      </div>
      
      <div class="info-box" style="border-left: 4px solid #dc3545;">
        <p><strong>⚠️ Important Notice:</strong></p>
        <p>Please ensure payment is made before the due date to avoid service interruption.</p>
      </div>
      
      <p>Thank you for using TRACES School Bus Service!</p>
      
      <div class="footer">
        <p>TRACES - School Bus Tracking System</p>
        <p>This is an automated notification. Please do not reply to this email.</p>
      </div>
    </div>
  </div>
</body>
</html>
            ''',
          );

          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    } catch (e) {
      print('Error sending payment reminder notifications: $e');
    }
  }
}
