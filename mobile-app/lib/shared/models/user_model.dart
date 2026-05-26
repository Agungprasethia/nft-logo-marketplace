import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String fullName;
  final String? username;
  final String email;
  final String? walletAddress;
  final String? profileImage;
  final String? title;
  final String? bio;
  final String? country;
  final String? motto;
  final String role; // 'user' or 'admin'
  final DateTime createdAt;
  final DateTime lastLogin;
  final List<int> ownedTokenIds;
  final List<int> createdTokenIds;
  
  // Social Links
  final String? instagram;
  final String? twitter;
  final String? website;
  final String? discord;

  UserModel({
    required this.uid,
    required this.fullName,
    this.username,
    required this.email,
    this.walletAddress,
    this.profileImage,
    this.title,
    this.bio,
    this.country,
    this.motto,
    this.role = 'user',
    required this.createdAt,
    required this.lastLogin,
    this.ownedTokenIds = const [],
    this.createdTokenIds = const [],
    this.instagram,
    this.twitter,
    this.website,
    this.discord,
  });

  UserModel copyWith({
    String? uid,
    String? fullName,
    String? username,
    String? email,
    String? walletAddress,
    String? profileImage,
    String? title,
    String? bio,
    String? country,
    String? motto,
    String? role,
    DateTime? createdAt,
    DateTime? lastLogin,
    List<int>? ownedTokenIds,
    List<int>? createdTokenIds,
    String? instagram,
    String? twitter,
    String? website,
    String? discord,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      fullName: fullName ?? this.fullName,
      username: username ?? this.username,
      email: email ?? this.email,
      walletAddress: walletAddress ?? this.walletAddress,
      profileImage: profileImage ?? this.profileImage,
      title: title ?? this.title,
      bio: bio ?? this.bio,
      country: country ?? this.country,
      motto: motto ?? this.motto,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      lastLogin: lastLogin ?? this.lastLogin,
      ownedTokenIds: ownedTokenIds ?? this.ownedTokenIds,
      createdTokenIds: createdTokenIds ?? this.createdTokenIds,
      instagram: instagram ?? this.instagram,
      twitter: twitter ?? this.twitter,
      website: website ?? this.website,
      discord: discord ?? this.discord,
    );
  }

  String get displayName {
    if (username != null && username!.isNotEmpty) return username!;
    if (fullName.isNotEmpty) return fullName;
    return walletAddressShort ?? email;
  }

  String? get walletAddressShort {
    if (walletAddress == null || walletAddress!.length <= 10) return walletAddress;
    return '${walletAddress!.substring(0, 6)}...${walletAddress!.substring(walletAddress!.length - 4)}';
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'fullName': fullName,
      if (username != null) 'username': username,
      'email': email,
      'walletAddress': walletAddress,
      'profileImage': profileImage,
      'title': title,
      'bio': bio,
      'country': country,
      'motto': motto,
      'role': role,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastLogin': Timestamp.fromDate(lastLogin),
      'ownedTokenIds': ownedTokenIds,
      'createdTokenIds': createdTokenIds,
      if (instagram != null) 'instagram': instagram,
      if (twitter != null) 'twitter': twitter,
      if (website != null) 'website': website,
      if (discord != null) 'discord': discord,
    };
  }

  factory UserModel.fromFirestore(Map<String, dynamic> json) {
    return UserModel(
      uid: json['uid'] as String? ?? '',
      fullName: json['fullName'] as String? ?? '',
      username: json['username'] as String?,
      email: json['email'] as String? ?? '',
      walletAddress: json['walletAddress'] as String?,
      profileImage: json['profileImage'] as String?,
      title: json['title'] as String?,
      bio: json['bio'] as String?,
      country: json['country'] as String?,
      motto: json['motto'] as String?,
      role: json['role'] as String? ?? 'user',
      createdAt: (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastLogin: (json['lastLogin'] as Timestamp?)?.toDate() ?? DateTime.now(),
      ownedTokenIds: (json['ownedTokenIds'] as List<dynamic>?)?.map((e) => e as int).toList() ?? [],
      createdTokenIds: (json['createdTokenIds'] as List<dynamic>?)?.map((e) => e as int).toList() ?? [],
      instagram: json['instagram'] as String?,
      twitter: json['twitter'] as String?,
      website: json['website'] as String?,
      discord: json['discord'] as String?,
    );
  }
}
