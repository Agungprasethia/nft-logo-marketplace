import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nft_logo_marketplace/shared/models/user_model.dart';
import 'package:nft_logo_marketplace/core/services/session_service.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/core/utils/route_utils.dart';

class AuthService {
  static final AuthService instance = AuthService._internal();
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// Real-time stream of the current user's Firestore profile
  Stream<UserModel?> get currentUserStream {
    return _auth.authStateChanges().asyncMap((user) async {
      if (user == null) return null;
      return getUserData(user.uid);
    });
  }

  /// Stream that updates whenever the user doc changes
  Stream<UserModel?> getUserStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (doc.exists) {
        return UserModel.fromFirestore(doc.data() as Map<String, dynamic>);
      }
      return null;
    });
  }

  Future<UserModel?> getUserData(String uid) async {
    try {
      DocumentSnapshot doc =
          await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        return UserModel.fromFirestore(doc.data() as Map<String, dynamic>);
      }
    } catch (e) {
      if (kDebugMode) { debugPrint('Error fetching user data: $e'); }
    }
    return null;
  }

  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    String? walletAddress,
  }) async {
    try {
      UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      String uid = userCredential.user!.uid;

      // Create user document in Firestore
      UserModel newUser = UserModel(
        uid: uid,
        fullName: fullName,
        email: email,
        walletAddress: walletAddress,
        role: 'admin', // Default role
        createdAt: DateTime.now(),
        lastLogin: DateTime.now(),
      );

      await _firestore.collection('users').doc(uid).set(newUser.toJson());

      return userCredential;
    } catch (e) {
      throw Exception('Failed to sign up: $e');
    }
  }

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      UserCredential userCredential =
          await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Update last login
      if (userCredential.user != null) {
        await _firestore
            .collection('users')
            .doc(userCredential.user!.uid)
            .update({
          'lastLogin': FieldValue.serverTimestamp(),
        });
      }

      return userCredential;
    } catch (e) {
      throw Exception('Failed to sign in: $e');
    }
  }

  Future<void> signOut() async {
    // 1. Clear session cache
    await SessionService.instance.fullLogout();
    
    // 2. Disconnect web3 to clear temporary state
    try {
      Web3Service.instance.disconnectWallet();
    } catch (e) {
      if (kDebugMode) { debugPrint('Error disconnecting wallet: $e'); }
    }

    // 3. Firebase sign out
    await _auth.signOut();
    
    // 4. Hard clear web history to prevent back-button admin dashboard reentry
    if (kIsWeb) {
      clearWebHistory();
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (_) {
      // Always show same message to prevent user enumeration
      // Do not differentiate between user-not-found and invalid-email
    }
  }

  Future<void> updateWalletAddress(String uid, String newWalletAddress) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'walletAddress': newWalletAddress,
      });
    } catch (e) {
      if (kDebugMode) { debugPrint('Error updating wallet address: $e'); }
      throw Exception('Failed to update wallet address: $e');
    }
  }
}
