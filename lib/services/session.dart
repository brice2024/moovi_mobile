import 'dart:async';

/// Utilisateur connecté, tel que renvoyé par l'API (`User.to_dict`).
class AppUser {
  final String id;
  final String? phoneNumber;
  final String? email;
  final String firstName;
  final String lastName;
  final String? photoUrl;
  final String role;
  final double rating;
  final int ridesCount;

  /// Identifiant du profil chauffeur (`drivers.id`), différent de [id].
  final String? driverId;
  final Map<String, dynamic> raw;

  const AppUser({
    required this.id,
    this.phoneNumber,
    this.email,
    this.firstName = '',
    this.lastName = '',
    this.photoUrl,
    this.role = 'passenger',
    this.rating = 0,
    this.ridesCount = 0,
    this.driverId,
    this.raw = const {},
  });

  bool get isDriver => driverId != null;

  String? get displayName {
    final name = '$firstName $lastName'.trim();
    return name.isEmpty ? null : name;
  }

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final driver = json['driver'];
    final email = json['email']?.toString();
    return AppUser(
      id: (json['id'] ?? json['userId'] ?? '').toString(),
      phoneNumber: json['phoneNumber']?.toString(),
      email: (email == null || email.isEmpty) ? null : email,
      firstName: json['firstName']?.toString() ?? '',
      lastName: json['lastName']?.toString() ?? '',
      photoUrl: json['photoUrl']?.toString(),
      role: json['role']?.toString() ?? 'passenger',
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      ridesCount: (json['ridesCount'] as num?)?.toInt() ?? 0,
      driverId: driver is Map ? driver['id']?.toString() : null,
      raw: json,
    );
  }
}

class AppSession {
  AppSession._();
  static final instance = AppSession._();
  final _changes = StreamController<AppUser?>.broadcast();
  AppUser? _user;
  AppUser? get currentUser => _user;
  Stream<AppUser?> get changes => _changes.stream;
  void setUser(AppUser? value) {
    _user = value;
    _changes.add(value);
  }
}
