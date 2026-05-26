import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class PinataService {
  // Authentication via JWT (API key/secret are embedded in the JWT)
  static const String _jwt = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySW5mb3JtYXRpb24iOnsiaWQiOiIxNDQxZjY3NS02OWYzLTQ2MWItYjVkZC1lNmQ2NDA5NjgzOTciLCJlbWFpbCI6InByYXNldGhpYXNwb3J0QGdtYWlsLmNvbSIsImVtYWlsX3ZlcmlmaWVkIjp0cnVlLCJwaW5fcG9saWN5Ijp7InJlZ2lvbnMiOlt7ImRlc2lyZWRSZXBsaWNhdGlvbkNvdW50IjoxLCJpZCI6IkZSQTEifSx7ImRlc2lyZWRSZXBsaWNhdGlvbkNvdW50IjoxLCJpZCI6Ik5ZQzEifV0sInZlcnNpb24iOjF9LCJtZmFfZW5hYmxlZCI6ZmFsc2UsInN0YXR1cyI6IkFDVElWRSJ9LCJhdXRoZW50aWNhdGlvblR5cGUiOiJzY29wZWRLZXkiLCJzY29wZWRLZXlLZXkiOiJjMDlhYzNmMDY2N2QyZDJkYTQ4MyIsInNjb3BlZEtleVNlY3JldCI6ImQwZjg4MjNjMTQ4ZGMzM2E2MWRlODJlNmY1ZjAyOGUxNmVjMTc1OWNlYWU3Y2UxYjk1Y2FjY2ZjZWE0ODIyOGIiLCJleHAiOjE4MDcwMTM2OTB9.yGOv-5Hqf1xsamn3KRPCufJ9h-xY0-iYlZsEqEmjLSs';
  static const String _pinFileUrl = 'https://api.pinata.cloud/pinning/pinFileToIPFS';
  static const String _pinJsonUrl = 'https://api.pinata.cloud/pinning/pinJSONToIPFS';

  static const String _gateway = 'https://gateway.pinata.cloud/ipfs/';

  /// Uploads image bytes to Pinata IPFS and returns the public gateway URL
  static Future<String> uploadImage(Uint8List imageBytes, String filename) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse(_pinFileUrl));

      // Use JWT Bearer token for authentication (more reliable)
      request.headers.addAll({
        'Authorization': 'Bearer $_jwt',
      });

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: filename,
          contentType: MediaType('image', 'png'),
        ),
      );

      // Add pinata metadata for better organization
      request.fields['pinataMetadata'] = jsonEncode({
        'name': filename,
        'keyvalues': {
          'app': 'LEO_NFT_Marketplace',
          'type': 'nft_image',
        },
      });

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final json = jsonDecode(responseBody);
        final ipfsHash = json['IpfsHash'];
        return '$_gateway$ipfsHash';
      } else {
        throw Exception('Failed to upload to Pinata: $responseBody');
      }
    } catch (e) {
      throw Exception('Pinata upload error: $e');
    }
  }

  /// Uploads NFT metadata JSON to Pinata IPFS and returns the gateway URL
  static Future<String> uploadMetadata({
    required String name,
    required String description,
    required String imageIpfsUrl,
    String category = 'Technology',
  }) async {
    try {
      final metadata = {
        'name': name,
        'description': description,
        'image': imageIpfsUrl,
        'category': category,
        'attributes': [
          {'trait_type': 'Platform', 'value': 'LEO NFT Marketplace'},
          {'trait_type': 'Category', 'value': category},
          {'trait_type': 'Created', 'value': DateTime.now().toIso8601String()},
        ],
      };

      final response = await http.post(
        Uri.parse(_pinJsonUrl),
        headers: {
          'Authorization': 'Bearer $_jwt',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'pinataContent': metadata,
          'pinataMetadata': {
            'name': '$name-metadata.json',
            'keyvalues': {
              'app': 'LEO_NFT_Marketplace',
              'type': 'nft_metadata',
            },
          },
        }),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final ipfsHash = json['IpfsHash'];
        return '$_gateway$ipfsHash';
      } else {
        throw Exception('Failed to upload metadata to Pinata: ${response.body}');
      }
    } catch (e) {
      throw Exception('Pinata metadata upload error: $e');
    }
  }

  /// Test connection to Pinata API
  static Future<bool> testConnection() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.pinata.cloud/data/testAuthentication'),
        headers: {
          'Authorization': 'Bearer $_jwt',
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
