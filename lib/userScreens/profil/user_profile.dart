/// Profil utilisateur renvoyé par l'API Moovi (`GET /api/users/me`).
class UserProfile {
  const UserProfile({
    required this.uid,
    this.firstName = '',
    this.lastName = '',
    this.phone = '',
    this.photoUrl,
    this.photoPath,
    this.rating = 0,
    this.ridesCount = 0,
  });

  final String uid;
  final String firstName;
  final String lastName;
  final String phone;
  final String? photoUrl; // URL publique servie par l'API
  final String? photoPath; // chemin du fichier côté API
  final double rating;
  final int ridesCount;

  String get fullName {
    final name = '$firstName $lastName'.trim();
    return name.isEmpty ? 'Utilisateur' : name;
  }

  factory UserProfile.fromMap(String uid, Map<String, dynamic>? data) {
    final d = data ?? const <String, dynamic>{};
    return UserProfile(
      uid: uid,
      firstName: d['firstName'] as String? ?? '',
      lastName: d['lastName'] as String? ?? '',
      phone: d['phone'] as String? ?? '',
      photoUrl: d['photoUrl'] as String?,
      photoPath: d['photoPath'] as String?,
      rating: (d['rating'] as num?)?.toDouble() ?? 0,
      ridesCount: (d['ridesCount'] as num?)?.toInt() ?? 0,
    );
  }
}
