import 'package:flutter/foundation.dart';
import 'package:nft_logo_marketplace/shared/models/user_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nft_logo_marketplace/core/services/auth_service.dart';

class UserService {
  static Future<void> saveProfile(UserModel user) async {
    final uid = AuthService.instance.currentUser?.uid ?? user.uid;
    if (uid.isEmpty) return;

    // 1. Save user profile
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'fullName': user.fullName,
      'username': user.username,
      'title': user.title,
      'bio': user.bio,
      'country': user.country,
      'motto': user.motto,
      'profileImage': user.profileImage,
      'walletAddress': user.walletAddress,
      'instagram': user.instagram,
      'twitter': user.twitter,
      'website': user.website,
      'discord': user.discord,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 2. Propagate creatorUsername to all NFTs created by this user
    final newUsername = (user.username != null && user.username!.isNotEmpty)
        ? user.username
        : null;

    try {
      final nftQuery = await FirebaseFirestore.instance
          .collection('nfts')
          .where('creatorId', isEqualTo: uid)
          .get();

      if (nftQuery.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in nftQuery.docs) {
          batch.update(doc.reference, {'creatorUsername': newUsername});
        }
        await batch.commit();
        if (kDebugMode) { debugPrint('✅ Updated creatorUsername on ${nftQuery.docs.length} NFTs'); }
      }
    } catch (e) {
      if (kDebugMode) { debugPrint('⚠️ Failed to propagate creatorUsername to NFTs: $e'); }
      // Non-critical — don't rethrow
    }
  }

  static Future<UserModel?> getProfile(String address) async {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid != null) {
      return AuthService.instance.getUserData(uid);
    }
    return null;
  }
}
