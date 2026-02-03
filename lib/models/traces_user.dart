class TracesUser {
  final String id;
  final String name;
  final UserRole role;
  final String? assignedServiceId;
  final String? email;

  const TracesUser({
    required this.id,
    required this.name,
    required this.role,
    this.assignedServiceId,
    this.email,
  });

  TracesUser copyWith({
    String? id,
    String? name,
    UserRole? role,
    String? assignedServiceId,
    String? email,
  }) {
    return TracesUser(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      assignedServiceId: assignedServiceId ?? this.assignedServiceId,
      email: email ?? this.email,
    );
  }
}

enum UserRole {
  passenger,
  driver,
}