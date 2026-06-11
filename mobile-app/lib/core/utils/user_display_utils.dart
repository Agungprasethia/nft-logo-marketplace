import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/shared/models/user_model.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';

class UserDisplayUtils {
  static String getDisplayName(UserModel? user, String walletAddress) {
    if (user != null && user.username != null && user.username!.isNotEmpty) {
      return user.username!;
    }
    return shortenAddress(walletAddress);
  }

  static String shortenAddress(String address) {
    if (address.isEmpty) return 'Unknown';
    if (address.length <= 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }

  static Widget buildAvatar(UserModel? user, String walletAddress, {double radius = 20, bool isFirst = false}) {
    final hasImage = user?.profileImage?.isNotEmpty == true;
    final isBase64 = hasImage && user?.profileImage?.startsWith('data:image') == true;
    
    final displayName = getDisplayName(user, walletAddress);
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasImage ? null : (isFirst ? AppColors.primaryGradient : null),
        color: hasImage ? null : (isFirst ? null : AppColors.surfaceLight),
        border: Border.all(color: isFirst ? AppColors.primary : AppColors.border, width: 2),
        image: hasImage 
          ? DecorationImage(
              image: isBase64 
                  ? MemoryImage(base64Decode((user?.profileImage ?? '').split(',').last)) as ImageProvider
                  : NetworkImage(user?.profileImage ?? ''),
              fit: BoxFit.cover,
            )
          : null,
      ),
      child: !hasImage 
          ? Center(
              child: Text(
                initial,
                style: AppTextStyles.labelMedium.copyWith(
                  color: isFirst ? Colors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: radius * 0.8,
                ),
              ),
            )
          : null,
    );
  }
}
