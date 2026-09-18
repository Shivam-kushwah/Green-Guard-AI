import 'package:cloud_firestore/cloud_firestore.dart';

/// Who someone is in the system. One app binary serves all four - the role on
/// the user document decides which home screen they land on.
enum UserRole {
  /// Scans crops, reports cases, requests expert review.
  farmer,

  /// Verified agronomist (KVK officer, agri-university staff) who answers
  /// review requests. Verdicts feed the learning loop.
  agronomist,

  /// State/district agriculture officer. Read-only access to the dashboard.
  officer,

  /// Can promote users and seed demo data.
  admin,
}

extension UserRoleX on UserRole {
  String get wire => name;

  String get label => switch (this) {
    UserRole.farmer => 'Farmer',
    UserRole.agronomist => 'Agronomist',
    UserRole.officer => 'Agriculture Officer',
    UserRole.admin => 'Administrator',
  };

  bool get canReview => this == UserRole.agronomist || this == UserRole.admin;
  bool get canViewDashboard =>
      this == UserRole.officer || this == UserRole.admin;

  static UserRole fromWire(String? v) => UserRole.values.firstWhere(
    (r) => r.name == v,
    orElse: () => UserRole.farmer,
  );
}

/// The cloud-side user profile.
///
/// Deliberately separate from the Hive [UserModel], which stays as the local
/// offline cache of the signed-in identity. This one carries the role, the
/// district and the expert credentials that the cloud features need.
class AppUser {
  final String uid;
  final String name;
  final String email;
  final String photoUrl;
  final UserRole role;

  /// Home district. Set at first sign-in from GPS, editable in the profile.
  final String? district;

  /// What this farmer actually grows - drives the weather risk screen.
  final List<String> crops;

  /// Agronomist-only credentials, shown to the farmer so they know who
  /// answered. An unverified agronomist cannot claim cases.
  final String? qualification;
  final String? institution;
  final bool verified;

  /// Running counts so the profile and dashboard avoid an expensive query.
  final int scanCount;
  final int reviewsCompleted;

  final DateTime createdAt;
  final DateTime? lastActiveAt;

  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.photoUrl,
    required this.role,
    required this.createdAt,
    this.district,
    this.crops = const [],
    this.qualification,
    this.institution,
    this.verified = false,
    this.scanCount = 0,
    this.reviewsCompleted = 0,
    this.lastActiveAt,
  });

  bool get isFarmer => role == UserRole.farmer;

  /// Only a *verified* agronomist may act on the review queue. The role alone
  /// is not enough - this is enforced again in the Firestore rules.
  bool get canReview => role.canReview && verified;

  bool get canViewDashboard => role.canViewDashboard;

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return AppUser(
      uid: doc.id,
      name: (d['name'] as String?) ?? '',
      email: (d['email'] as String?) ?? '',
      photoUrl: (d['photoUrl'] as String?) ?? '',
      role: UserRoleX.fromWire(d['role'] as String?),
      district: d['district'] as String?,
      crops: List<String>.from((d['crops'] as List?) ?? const []),
      qualification: d['qualification'] as String?,
      institution: d['institution'] as String?,
      verified: (d['verified'] as bool?) ?? false,
      scanCount: (d['scanCount'] as num?)?.toInt() ?? 0,
      reviewsCompleted: (d['reviewsCompleted'] as num?)?.toInt() ?? 0,
      createdAt:
          (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastActiveAt: (d['lastActiveAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'name': name,
    'email': email,
    'photoUrl': photoUrl,
    'role': role.wire,
    'district': district,
    'crops': crops,
    'qualification': qualification,
    'institution': institution,
    'verified': verified,
    'scanCount': scanCount,
    'reviewsCompleted': reviewsCompleted,
    'createdAt': Timestamp.fromDate(createdAt),
    'lastActiveAt': lastActiveAt == null
        ? null
        : Timestamp.fromDate(lastActiveAt!),
  };

  AppUser copyWith({
    String? name,
    UserRole? role,
    String? district,
    List<String>? crops,
    String? qualification,
    String? institution,
    bool? verified,
    int? scanCount,
    int? reviewsCompleted,
    DateTime? lastActiveAt,
  }) => AppUser(
    uid: uid,
    name: name ?? this.name,
    email: email,
    photoUrl: photoUrl,
    role: role ?? this.role,
    district: district ?? this.district,
    crops: crops ?? this.crops,
    qualification: qualification ?? this.qualification,
    institution: institution ?? this.institution,
    verified: verified ?? this.verified,
    scanCount: scanCount ?? this.scanCount,
    reviewsCompleted: reviewsCompleted ?? this.reviewsCompleted,
    createdAt: createdAt,
    lastActiveAt: lastActiveAt ?? this.lastActiveAt,
  );
}
