import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nft_logo_marketplace/shared/models/logo_nft.dart';

import 'package:nft_logo_marketplace/core/config/app_config.dart';

class ApiService {
  static final ApiService instance = ApiService._internal();

  factory ApiService() {
    return instance;
  }

  ApiService._internal();

  // Centralized configurable API base URL
  static String get baseUrl {
    return const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: AppConfig.apiBaseUrl,
    );
  }

  // Local Memory Cache
  List<LogoNFT>? _cachedNFTs;
  DateTime? _lastFetchTime;
  static const Duration _cacheValidDuration = Duration(minutes: 5);

  /// Force clear the local cache
  void clearCache() {
    _cachedNFTs = null;
    _lastFetchTime = null;
    if (kDebugMode) { debugPrint('🧹 Local NFT cache cleared'); }
  }

  /// Fetch all NFTs from the backend API
  Future<List<LogoNFT>> fetchAllNFTs({bool forceRefresh = false}) async {
    // Return cached data if valid and not forced
    if (!forceRefresh && _cachedNFTs != null && _lastFetchTime != null) {
      if (DateTime.now().difference(_lastFetchTime!) < _cacheValidDuration) {
        if (kDebugMode) { debugPrint('⚡ Returning cached NFTs (${_cachedNFTs!.length} items)'); }
        return _cachedNFTs!;
      }
    }

    if (kDebugMode) { debugPrint('🌐 Loading NFTs from backend API...'); }
    try {
      final response = await http.get(Uri.parse('$baseUrl/nft/all'));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final List<LogoNFT> logos = data.map((json) {
          // Add tokenId field if it's missing but we have id
          if (json['tokenId'] == null && json['id'] != null) {
             json['tokenId'] = int.tryParse(json['id'].toString()) ?? 0;
          }
          return LogoNFT.fromJson(json);
        }).toList();

        _cachedNFTs = logos;
        _lastFetchTime = DateTime.now();

        if (kDebugMode) { debugPrint('✅ Backend NFT batch loaded: ${logos.length}'); }
        if (kDebugMode) { debugPrint('⚡ Firestore realtime listeners preserved'); }

        return logos;
      } else {
        throw Exception('Failed to load NFTs from API. Status Code: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ API fetchAllNFTs Error: $e'); }
      throw Exception('Failed to load NFTs: $e');
    }
  }

  /// Fetch a single NFT by ID from the backend API
  Future<LogoNFT?> fetchNFTById(int tokenId) async {
    // Check cache first for faster response
    if (_cachedNFTs != null) {
      try {
        final cached = _cachedNFTs!.firstWhere((nft) => nft.tokenId == tokenId);
        return cached;
      } catch (e) {
        // Not found in cache, proceed to fetch
      }
    }

    try {
      final response = await http.get(Uri.parse('$baseUrl/nft/$tokenId'));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['tokenId'] == null && data['id'] != null) {
           data['tokenId'] = int.tryParse(data['id'].toString()) ?? 0;
        }
        return LogoNFT.fromJson(data);
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('Failed to load NFT $tokenId from API. Status Code: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ API fetchNFTById Error: $e'); }
      return null;
    }
  }
}
