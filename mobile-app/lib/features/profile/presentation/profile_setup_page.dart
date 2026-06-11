import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nft_logo_marketplace/core/services/user_service.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/shared/models/user_model.dart';
import 'package:nft_logo_marketplace/features/nft/presentation/home_page.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';

/// Mandatory profile onboarding screen.
///
/// Shown immediately after a new wallet connects for the first time
/// (or when [UserModel.isProfileComplete] returns false on session restore).
///
/// Rules:
///  - No back navigation (PopScope prevents any back gesture)
///  - No skip button
///  - Only "Save & Continue" proceeds
///  - On save: writes via [UserService.saveProfile], then navigates to [HomePage]
///    with [pushAndRemoveUntil] so no back-stack remains.
class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({super.key});

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  // Required fields
  late final TextEditingController _usernameController;
  late final TextEditingController _nameController;
  String? _selectedCountry;

  // Optional fields
  late final TextEditingController _bioController;
  String? _avatarBase64;

  bool _isLoading = false;
  String? _errorMessage;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  final List<String> _countryOptions = [
    'Indonesia',
    'United States',
    'Japan',
    'South Korea',
    'United Kingdom',
    'Singapore',
    'Malaysia',
    'Australia',
    'Germany',
    'France',
    'Canada',
    'Brazil',
    'India',
    'Netherlands',
    'Sweden',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _nameController = TextEditingController();
    _bioController = TextEditingController();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _nameController.dispose();
    _bioController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  // ── Avatar picker ──────────────────────────────────────────────────────────

  Future<void> _pickAvatar() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _avatarBase64 = 'data:image/png;base64,${base64Encode(bytes)}';
      });
    } catch (_) {}
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _saveProfile() async {
    setState(() => _errorMessage = null);

    // Validate required fields manually before form validate
    final username = _usernameController.text.trim();
    final fullName = _nameController.text.trim();
    final country = _selectedCountry;

    if (username.isEmpty || fullName.isEmpty || country == null || country.isEmpty) {
      setState(() {
        _errorMessage = 'Please complete all required profile information.';
      });
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      final walletAddress = Web3Service.instance.currentAddress;

      final uid = firebaseUser?.uid ?? walletAddress ?? 'unknown';

      final user = UserModel(
        uid: uid,
        fullName: fullName,
        username: username,
        email: firebaseUser?.email ?? '',
        walletAddress: walletAddress,
        country: country,
        bio: _bioController.text.trim().isNotEmpty ? _bioController.text.trim() : null,
        profileImage: _avatarBase64,
        role: 'user',
        createdAt: DateTime.now(),
        lastLogin: DateTime.now(),
      );

      await UserService.saveProfile(user);

      if (!mounted) return;

      // Navigate to HomePage, clearing entire back-stack so user cannot go back.
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const HomePage(),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to save profile. Please try again.';
        _isLoading = false;
      });
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // PopScope with canPop: false completely blocks back navigation.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            // Background glow
            Positioned.fill(
              child: CustomPaint(painter: _BackgroundPainter()),
            ),

            SafeArea(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Column(
                    children: [
                      // ── Header ───────────────────────────────────────────
                      _buildHeader(),

                      // ── Form ─────────────────────────────────────────────
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.xl, AppSpacing.lg,
                            AppSpacing.xl, 40,
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Avatar
                                _buildAvatarPicker(),
                                const SizedBox(height: AppSpacing.xxl),

                                // Required section header
                                _sectionLabel('REQUIRED INFORMATION'),
                                const SizedBox(height: AppSpacing.md),

                                // Username
                                _buildField(
                                  controller: _usernameController,
                                  label: 'Username *',
                                  hint: 'e.g. AgungNFT',
                                  prefixIcon: Icons.alternate_email,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) return 'Username is required';
                                    if (v.trim().length < 3) return 'At least 3 characters';
                                    if (v.trim().length > 20) return 'Max 20 characters';
                                    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(v.trim())) {
                                      return 'Only letters, numbers, and underscores';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: AppSpacing.md),

                                // Full Name
                                _buildField(
                                  controller: _nameController,
                                  label: 'Full Name *',
                                  hint: 'e.g. Agung Prasethia',
                                  prefixIcon: Icons.person_outline,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) return 'Full name is required';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: AppSpacing.md),

                                // Country dropdown
                                _buildCountryDropdown(),
                                const SizedBox(height: AppSpacing.xxl),

                                // Optional section header
                                _sectionLabel('OPTIONAL'),
                                const SizedBox(height: AppSpacing.md),

                                // Bio
                                _buildField(
                                  controller: _bioController,
                                  label: 'Bio',
                                  hint: 'Tell the world about yourself and your art...',
                                  maxLines: 3,
                                  maxLength: 250,
                                ),
                                const SizedBox(height: AppSpacing.xxl),

                                // Error message
                                if (_errorMessage != null) ...[
                                  _buildErrorBanner(),
                                  const SizedBox(height: AppSpacing.lg),
                                ],

                                // Save button
                                _buildSaveButton(),
                                const SizedBox(height: AppSpacing.xl),

                                // Footer disclaimer
                                Text(
                                  'This information will be visible to other marketplace participants.',
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.textSecondary.withValues(alpha: 0.6),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.12),
            AppColors.background,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          // Step chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_add_alt_1, color: AppColors.primary, size: 14),
                const SizedBox(width: 6),
                Text(
                  'PROFILE SETUP',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primary,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Complete Your Profile',
            style: AppTextStyles.h2.copyWith(fontWeight: FontWeight.w900),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Set up your identity before entering the marketplace.\nThis step is required for all new participants.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarPicker() {
    return Center(
      child: GestureDetector(
        onTap: _isLoading ? null : _pickAvatar,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surfaceLight,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.5),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ],
                image: _avatarBase64 != null
                    ? DecorationImage(
                        image: MemoryImage(
                          base64Decode(_avatarBase64!.split(',')[1]),
                        ),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: _avatarBase64 == null
                  ? const Icon(Icons.person, size: 48, color: AppColors.textSecondary)
                  : null,
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.background, width: 2),
                ),
                child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: AppTextStyles.labelSmall.copyWith(
        color: AppColors.textSecondary,
        letterSpacing: 1.2,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    IconData? prefixIcon,
    String? Function(String?)? validator,
    int maxLines = 1,
    int? maxLength,
  }) {
    return TextFormField(
      controller: controller,
      style: AppTextStyles.bodyMedium,
      maxLines: maxLines,
      minLines: 1,
      maxLength: maxLength,
      enabled: !_isLoading,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: AppColors.textSecondary, size: 20)
            : null,
        labelStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
        hintStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textSecondary.withValues(alpha: 0.45),
        ),
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
          borderSide: BorderSide(color: AppColors.danger.withValues(alpha: 0.6)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md,
        ),
      ),
    );
  }

  Widget _buildCountryDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedCountry,
      dropdownColor: AppColors.surface,
      style: AppTextStyles.bodyMedium,
      hint: Text(
        'Select your country',
        style: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textSecondary.withValues(alpha: 0.45),
        ),
      ),
      decoration: InputDecoration(
        labelText: 'Country *',
        prefixIcon: const Icon(Icons.public, color: AppColors.textSecondary, size: 20),
        labelStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
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
          borderSide: BorderSide(color: AppColors.danger.withValues(alpha: 0.6)),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md,
        ),
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'Please select your country' : null,
      items: _countryOptions
          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
          .toList(),
      onChanged: _isLoading ? null : (v) => setState(() => _selectedCountry = v),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _saveProfile,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.surfaceLight,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          elevation: _isLoading ? 0 : 8,
          shadowColor: AppColors.primary.withValues(alpha: 0.5),
        ),
        child: _isLoading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_outline, size: 20, color: Colors.white),
                  const SizedBox(width: 10),
                  Text(
                    'Save & Enter Marketplace',
                    style: AppTextStyles.labelLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Background painter ────────────────────────────────────────────────────────

class _BackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p1 = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.07)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 120);
    canvas.drawCircle(Offset(size.width * 0.15, size.height * 0.1), 200, p1);

    final p2 = Paint()
      ..color = AppColors.secondary.withValues(alpha: 0.05)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 150);
    canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.85), 220, p2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
