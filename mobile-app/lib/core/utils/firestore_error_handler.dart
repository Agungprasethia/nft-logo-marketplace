import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/shared/widgets/firestore_index_preparing_state.dart';

/// Centralized Firestore error detection and handling utility.
///
/// Prevents raw Firebase errors from ever reaching production users.
/// All Firestore StreamBuilder/FutureBuilder error branches should
/// route through this class.
class FirestoreErrorHandler {
  FirestoreErrorHandler._();

  // ════════════════════════════════════════════════════════════════
  // Error Type Detection
  // ════════════════════════════════════════════════════════════════

  /// Returns true if the error is a missing Firestore index.
  static bool isIndexError(Object? error) {
    if (error is FirebaseException) {
      if (error.code == 'failed-precondition' &&
          error.message != null &&
          error.message!.toLowerCase().contains('index')) {
        return true;
      }
    }
    // Fallback: check string representation for non-Firebase wrappers
    final msg = error.toString().toLowerCase();
    return msg.contains('failed-precondition') &&
        msg.contains('index');
  }

  /// Returns true if the error is a permission denial.
  static bool isPermissionError(Object? error) {
    if (error is FirebaseException) {
      return error.code == 'permission-denied';
    }
    final msg = error.toString().toLowerCase();
    return msg.contains('permission-denied') ||
        msg.contains('permission denied');
  }

  /// Returns true if the error is a network/availability failure.
  static bool isNetworkError(Object? error) {
    if (error is FirebaseException) {
      return error.code == 'unavailable';
    }
    final msg = error.toString().toLowerCase();
    return msg.contains('unavailable') ||
        msg.contains('network-request-failed') ||
        msg.contains('network error');
  }

  // ════════════════════════════════════════════════════════════════
  // Debug Tooling
  // ════════════════════════════════════════════════════════════════

  /// Extracts the Firebase Console index-creation URL from an error, if present.
  static String? extractIndexUrl(Object? error) {
    if (error is FirebaseException && error.message != null) {
      final regex = RegExp(r'https://console\.firebase\.google\.com\S+');
      final match = regex.firstMatch(error.message!);
      return match?.group(0);
    }
    return null;
  }

  /// Logs the full error details **only** in debug mode.
  /// In release builds this is a complete no-op.
  static void logDebugError(Object? error, {String context = ''}) {
    if (kDebugMode) {
      debugPrint('╔══════════════════════════════════════════════════');
      debugPrint('║ 🔥 FIRESTORE ERROR ${context.isNotEmpty ? '[$context]' : ''}');
      debugPrint('║ Type : ${_classifyError(error)}');
      debugPrint('║ Detail: $error');
      final url = extractIndexUrl(error);
      if (url != null) {
        debugPrint('║ 🔗 Index URL: $url');
      }
      debugPrint('╚══════════════════════════════════════════════════');
    }
  }

  static String _classifyError(Object? error) {
    if (isIndexError(error)) return 'MISSING_INDEX';
    if (isPermissionError(error)) return 'PERMISSION_DENIED';
    if (isNetworkError(error)) return 'NETWORK_UNAVAILABLE';
    return 'UNKNOWN';
  }

  // ════════════════════════════════════════════════════════════════
  // UI Widget Builder — drop-in replacement for error branches
  // ════════════════════════════════════════════════════════════════

  /// Returns a premium fallback widget based on error type.
  ///
  /// Usage inside any StreamBuilder / FutureBuilder:
  /// ```dart
  /// if (snapshot.hasError) {
  ///   return FirestoreErrorHandler.buildErrorWidget(
  ///     snapshot.error,
  ///     onRetry: () => setState(() {}),
  ///   );
  /// }
  /// ```
  static Widget buildErrorWidget(
    Object? error, {
    VoidCallback? onRetry,
  }) {
    // Always log in debug mode
    logDebugError(error);

    if (isIndexError(error)) {
      return FirestoreIndexPreparingState(
        title: 'Marketplace Data Preparing',
        message:
            'This feature is currently initializing blockchain indexes. '
            'Please try again shortly.',
        icon: Icons.sync,
        onRetry: onRetry,
      );
    }

    if (isPermissionError(error)) {
      return FirestoreIndexPreparingState(
        title: 'Access Restricted',
        message:
            'You do not have permission to view this data. '
            'Please verify your wallet connection.',
        icon: Icons.lock_outline,
        onRetry: onRetry,
      );
    }

    if (isNetworkError(error)) {
      return FirestoreIndexPreparingState(
        title: 'Blockchain Network Unavailable',
        message:
            'Unable to reach the marketplace backend. '
            'Please check your internet connection and try again.',
        icon: Icons.cloud_off_outlined,
        onRetry: onRetry,
      );
    }

    // Generic fallback — still premium, never raw
    return FirestoreIndexPreparingState(
      title: 'Marketplace Syncing',
      message:
          'Something went wrong while loading data. '
          'Please try again shortly.',
      icon: Icons.refresh,
      onRetry: onRetry,
    );
  }
}
