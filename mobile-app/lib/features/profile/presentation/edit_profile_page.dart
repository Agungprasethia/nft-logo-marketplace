import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nft_logo_marketplace/shared/models/user_model.dart';
import 'package:nft_logo_marketplace/core/services/user_service.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/core/theme/app_shadows.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/utils/notification_manager.dart';
import 'package:nft_logo_marketplace/shared/models/app_notification.dart';

class EditProfilePage extends StatefulWidget {
  final UserModel user;

  const EditProfilePage({super.key, required this.user});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  
  // Basic Info
  late TextEditingController _nameController;
  late TextEditingController _usernameController;
  late TextEditingController _bioController;
  late TextEditingController _mottoController;
  
  String? _selectedTitle;
  String? _selectedCountry;

  final List<String> _titleOptions = [
    '3D Artist',
    'Graphic Designer',
    'Digital Illustrator',
    'NFT Creator',
    'Pixel Artist',
    'Collector',
    'Other'
  ];

  final List<String> _countryOptions = [
    'Indonesia',
    'United States',
    'Japan',
    'South Korea',
    'United Kingdom',
    'Singapore',
    'Malaysia',
    'Australia',
    'Other'
  ];
  
  // Social Links
  late TextEditingController _instagramController;
  late TextEditingController _twitterController;
  late TextEditingController _websiteController;
  late TextEditingController _discordController;
  
  final _picker = ImagePicker();
  String? _avatarUrl;
  bool _isLoading = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.fullName);
    _usernameController = TextEditingController(text: widget.user.username ?? '');
    _bioController = TextEditingController(text: widget.user.bio ?? '');
    _mottoController = TextEditingController(text: widget.user.motto ?? '');
    
    final initialTitle = widget.user.title;
    if (initialTitle != null && initialTitle.isNotEmpty) {
      if (_titleOptions.contains(initialTitle)) {
        _selectedTitle = initialTitle;
      } else {
        _selectedTitle = 'Other';
      }
    }

    final initialCountry = widget.user.country;
    if (initialCountry != null && initialCountry.isNotEmpty) {
      if (_countryOptions.contains(initialCountry)) {
        _selectedCountry = initialCountry;
      } else {
        _selectedCountry = 'Other';
      }
    }
    
    _instagramController = TextEditingController(text: widget.user.instagram ?? '');
    _twitterController = TextEditingController(text: widget.user.twitter ?? '');
    _websiteController = TextEditingController(text: widget.user.website ?? '');
    _discordController = TextEditingController(text: widget.user.discord ?? '');
    
    _avatarUrl = widget.user.profileImage;

    // Listeners for detecting changes
    void markChanged() {
      if (!_hasChanges) setState(() => _hasChanges = true);
    }
    
    _nameController.addListener(markChanged);
    _usernameController.addListener(markChanged);
    _bioController.addListener(markChanged);
    _mottoController.addListener(markChanged);
    _instagramController.addListener(markChanged);
    _twitterController.addListener(markChanged);
    _websiteController.addListener(markChanged);
    _discordController.addListener(markChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _mottoController.dispose();
    _instagramController.dispose();
    _twitterController.dispose();
    _websiteController.dispose();
    _discordController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      if (image == null) return;

      final bytes = await image.readAsBytes();
      final base64String = 'data:image/png;base64,${base64Encode(bytes)}';

      setState(() {
        _avatarUrl = base64String;
        _hasChanges = true;
      });
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog('Failed to pick image');
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;
    
    final shouldPop = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.1),
                blurRadius: 20,
                spreadRadius: 2,
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 48, color: AppColors.accentOrange),
              const SizedBox(height: AppSpacing.md),
              const Text('Discard Changes?', style: AppTextStyles.h3),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'You have unsaved changes. Are you sure you want to discard them?',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Cancel', style: AppTextStyles.labelLarge),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text('Discard', style: AppTextStyles.labelLarge.copyWith(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    
    return shouldPop ?? false;
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
              const SizedBox(height: AppSpacing.md),
              const Text('Error', style: AppTextStyles.h3),
              const SizedBox(height: AppSpacing.sm),
              Text(message, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary), textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.surfaceLight),
                  child: const Text('OK'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSuccessDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(color: AppColors.success.withValues(alpha: 0.1), blurRadius: 20, spreadRadius: 2)
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 48, color: AppColors.success),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text('Profile Saved', style: AppTextStyles.h3),
              const SizedBox(height: AppSpacing.sm),
              Text('Your changes have been published successfully.', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary), textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text('Continue', style: AppTextStyles.labelLarge.copyWith(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Additional validation check if needed
    if (_nameController.text.trim().isEmpty) {
      _showErrorDialog('Display name cannot be empty.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final updatedUser = widget.user.copyWith(
        fullName: _nameController.text.trim(),
        username: _usernameController.text.trim().isNotEmpty ? _usernameController.text.trim() : null,
        title: _selectedTitle,
        bio: _bioController.text.trim().isNotEmpty ? _bioController.text.trim() : null,
        country: _selectedCountry,
        motto: _mottoController.text.trim().isNotEmpty ? _mottoController.text.trim() : null,
        instagram: _instagramController.text.trim().isNotEmpty ? _instagramController.text.trim() : null,
        twitter: _twitterController.text.trim().isNotEmpty ? _twitterController.text.trim() : null,
        website: _websiteController.text.trim().isNotEmpty ? _websiteController.text.trim() : null,
        discord: _discordController.text.trim().isNotEmpty ? _discordController.text.trim() : null,
        profileImage: _avatarUrl,
      );

      await UserService.saveProfile(updatedUser);

      if (!mounted) return;
      setState(() {
        _hasChanges = false;
      });
      
      await _showSuccessDialog();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog('Failed to save profile. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  InputDecoration _premiumInputDecoration(String label, String hint, {IconData? prefixIcon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: AppColors.textSecondary) : null,
      labelStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
      hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary.withValues(alpha: 0.5)),
      filled: true,
      fillColor: AppColors.surfaceLight.withValues(alpha: 0.3),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: BorderSide(color: AppColors.danger.withValues(alpha: 0.5)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md, top: AppSpacing.lg),
      child: Text(
        title.toUpperCase(),
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.textSecondary,
          letterSpacing: 1.2,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background.withValues(alpha: 0.9),
          title: const Text('Edit Profile', style: AppTextStyles.h3),
          centerTitle: true,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (_hasChanges) {
                final shouldPop = await _onWillPop();
                if (shouldPop && context.mounted) Navigator.pop(context);
              } else {
                Navigator.pop(context);
              }
            },
          ),
          actions: [
            if (_hasChanges && !_isLoading)
              TextButton(
                onPressed: _saveProfile,
                child: Text('Save', style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary)),
              ),
          ],
        ),
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
                sliver: SliverToBoxAdapter(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header Profile Picture
                        Center(
                          child: GestureDetector(
                            onTap: _pickImage,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceLight,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.5), width: 2),
                                    boxShadow: [
                                      BoxShadow(color: AppColors.primary.withValues(alpha: 0.15), blurRadius: 20, spreadRadius: 5),
                                    ],
                                    image: _avatarUrl != null && _avatarUrl!.startsWith('data:image')
                                        ? DecorationImage(
                                            image: MemoryImage(base64Decode(_avatarUrl!.split(',')[1])),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child: _avatarUrl == null || !_avatarUrl!.startsWith('data:image')
                                      ? const Icon(Icons.person, size: 60, color: AppColors.textSecondary)
                                      : null,
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      border: Border.all(color: AppColors.border),
                                      shape: BoxShape.circle,
                                      boxShadow: AppShadows.soft,
                                    ),
                                    child: const Icon(Icons.edit_outlined, size: 18, color: AppColors.textPrimary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        
                        // Badges/Wallet
                        Center(
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(100.0),
                                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.verified, size: 14, color: AppColors.primary),
                                    const SizedBox(width: 4),
                                    Text('Verified Creator', style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: AppSpacing.xxl),

                        // Section 1: Basic Information
                        _buildSectionHeader('Basic Information'),
                        TextFormField(
                          controller: _usernameController,
                          style: AppTextStyles.bodyMedium,
                          decoration: _premiumInputDecoration('Username', 'e.g. AgungNFT', prefixIcon: Icons.alternate_email),
                          validator: (value) {
                            if (value != null && value.trim().isNotEmpty) {
                              if (value.length < 3) return 'Username must be at least 3 characters';
                              if (value.length > 20) return 'Username cannot exceed 20 characters';
                              if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
                                return 'Only letters, numbers, and underscores allowed';
                              }
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _nameController,
                          style: AppTextStyles.bodyMedium,
                          decoration: _premiumInputDecoration('Display Name', 'e.g. Satoshi Nakamoto', prefixIcon: Icons.person_outline),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return 'Display Name is required';
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedTitle,
                          dropdownColor: AppColors.surface,
                          style: AppTextStyles.bodyMedium,
                          decoration: _premiumInputDecoration('Creative Title', 'Select your title', prefixIcon: Icons.badge_outlined),
                          items: _titleOptions.map((title) => DropdownMenuItem(
                            value: title,
                            child: Text(title),
                          )).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedTitle = value;
                              _hasChanges = true;
                            });
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedCountry,
                          dropdownColor: AppColors.surface,
                          style: AppTextStyles.bodyMedium,
                          decoration: _premiumInputDecoration('Country', 'Select your country', prefixIcon: Icons.public),
                          items: _countryOptions.map((country) => DropdownMenuItem(
                            value: country,
                            child: Text(country),
                          )).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedCountry = value;
                              _hasChanges = true;
                            });
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _mottoController,
                          style: AppTextStyles.bodyMedium,
                          decoration: _premiumInputDecoration('Motto', 'e.g. Code is Poetry', prefixIcon: Icons.format_quote),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _bioController,
                          style: AppTextStyles.bodyMedium,
                          maxLines: null,
                          minLines: 3,
                          maxLength: 250,
                          keyboardType: TextInputType.multiline,
                          decoration: _premiumInputDecoration('Bio', 'Tell the world about yourself and your art...'),
                        ),

                        const SizedBox(height: AppSpacing.xl),

                        // Section 2: Social Links (Optional)
                        _buildSectionHeader('Social Links (Optional)'),
                        TextFormField(
                          controller: _twitterController,
                          style: AppTextStyles.bodyMedium,
                          decoration: _premiumInputDecoration('Twitter/X', 'https://twitter.com/username', prefixIcon: Icons.alternate_email),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _instagramController,
                          style: AppTextStyles.bodyMedium,
                          decoration: _premiumInputDecoration('Instagram', 'https://instagram.com/username', prefixIcon: Icons.camera_alt_outlined),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _discordController,
                          style: AppTextStyles.bodyMedium,
                          decoration: _premiumInputDecoration('Discord', 'Username#1234', prefixIcon: Icons.discord),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _websiteController,
                          style: AppTextStyles.bodyMedium,
                          keyboardType: TextInputType.url,
                          decoration: _premiumInputDecoration('Website', 'https://yourwebsite.com', prefixIcon: Icons.language),
                          validator: (value) {
                            if (value != null && value.isNotEmpty) {
                              final urlPattern = r'^(https?:\\/\\/)?([\\da-z\\.-]+)\\.([a-z\\.]{2,6})([\\/\\w \\.-]*)*\\/?$';
                              if (!RegExp(urlPattern).hasMatch(value)) return 'Enter a valid URL';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: AppSpacing.xl),

                        // Section 3: Wallet Information
                        _buildSectionHeader('Wallet Information'),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceLight,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.account_balance_wallet_outlined, color: AppColors.textSecondary),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text('Connected Wallet', style: AppTextStyles.labelMedium),
                                        const SizedBox(width: 8),
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: AppColors.success,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.user.walletAddress ?? 'Not connected',
                                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy, size: 20, color: AppColors.textSecondary),
                                onPressed: () {
                                  if (widget.user.walletAddress != null) {
                                    Clipboard.setData(ClipboardData(text: widget.user.walletAddress!));
                                    NotificationManager.show(
                                      context: context,
                                      title: 'Copied',
                                      message: 'Address copied to clipboard!',
                                      type: NotificationType.info,
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 60),

                        // Save Button
                        ElevatedButton(
                          onPressed: _isLoading || !_hasChanges ? null : _saveProfile,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            backgroundColor: AppColors.primary,
                            disabledBackgroundColor: AppColors.surfaceLight,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                            ),
                            elevation: _isLoading || !_hasChanges ? 0 : 8,
                            shadowColor: AppColors.primary.withValues(alpha: 0.4),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Save Changes',
                                  style: AppTextStyles.labelLarge.copyWith(
                                    color: _hasChanges ? Colors.white : AppColors.textSecondary,
                                  ),
                                ),
                        ),
                        const SizedBox(height: AppSpacing.xxxl),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
