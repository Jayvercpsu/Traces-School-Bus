import 'location_point.dart';

enum ServiceStatus { preparing, onTheWay, arrived, completed }

class SchoolService {
  final String id;
  final String routeName;
  final String driverId;
  final String driverName;
  final String driverContact;
  final String busPlateNumber;
  final String busModel;
  final List<String> passengerIds;
  final LocationPoint currentLocation;
  final LocationPoint? destinationLocation;
  final DateTime eta;
  final ServiceStatus status;
  final Map<String, DateTime> paymentDueDates;

  SchoolService({
    required this.id,
    required this.routeName,
    required this.driverId,
    required this.driverName,
    required this.driverContact,
    required this.busPlateNumber,
    required this.busModel,
    required this.passengerIds,
    required this.currentLocation,
    required this.destinationLocation,
    required this.eta,
    required this.status,
    required this.paymentDueDates,
  });

  SchoolService copyWith({
    String? id,
    String? routeName,
    String? driverId,
    String? driverName,
    String? driverContact,
    String? busPlateNumber,
    String? busModel,
    List<String>? passengerIds,
    LocationPoint? currentLocation,
    LocationPoint? destinationLocation,
    DateTime? eta,
    ServiceStatus? status,
    Map<String, DateTime>? paymentDueDates,
  }) {
    return SchoolService(
      id: id ?? this.id,
      routeName: routeName ?? this.routeName,
      driverId: driverId ?? this.driverId,
      driverName: driverName ?? this.driverName,
      driverContact: driverContact ?? this.driverContact,
      busPlateNumber: busPlateNumber ?? this.busPlateNumber,
      busModel: busModel ?? this.busModel,
      passengerIds: passengerIds ?? this.passengerIds,
      currentLocation: currentLocation ?? this.currentLocation,
      destinationLocation: destinationLocation ?? this.destinationLocation,
      eta: eta ?? this.eta,
      status: status ?? this.status,
      paymentDueDates: paymentDueDates ?? this.paymentDueDates,
    );
  }
}
