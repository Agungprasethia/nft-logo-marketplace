  import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/features/admin/presentation/pending_nft_page.dart';
import 'package:nft_logo_marketplace/features/admin/presentation/approved_nft_page.dart';
import 'package:nft_logo_marketplace/features/admin/presentation/active_auctions_page.dart';
import 'package:nft_logo_marketplace/features/admin/presentation/user_management_page.dart';
import 'package:nft_logo_marketplace/features/admin/presentation/reported_nft_page.dart';
import 'package:nft_logo_marketplace/features/admin/presentation/re_auction_requests_page.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';
import 'package:nft_logo_marketplace/core/services/auth_service.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/shared/widgets/glass_card.dart';
import 'package:nft_logo_marketplace/core/utils/responsive_layout.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;

  final List<String> _menuItems = [
    'Dashboard',
    'Pending NFTs',
    'Approved NFTs',
    'Active Auctions',
    'User Management',
    'Reported NFTs',
    'Re-Auction Requests',
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveLayout.isDesktop(context);
    
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          if (isDesktop) _buildSidebar(),
          Expanded(
            child: Container(
              color: AppColors.background,
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(child: _getPageContent()),
                ],
              ),
            ),
          ),
        ],
      ),
      drawer: !isDesktop
          ? Drawer(child: _buildSidebar())
          : null,
    );
  }

  Widget _getPageContent() {
    switch (_selectedIndex) {
      case 0:
        return _buildDashboardOverview();
      case 1:
        return const PendingNftPage();
      case 2:
        return const ApprovedNftPage();
      case 3:
        return const ActiveAuctionsPage();
      case 4:
        return const UserManagementPage();
      case 5:
        return const ReportedNftPage();
      case 6:
        return const ReAuctionRequestsPage();
      default:
        return _buildDashboardOverview();
    }
  }

  Widget _buildDashboardOverview() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Real-Time Stats from Firestore ──
          Builder(
            builder: (context) {
              final statCards = [
                _buildFirestoreStatCard('Total Users', FirestoreService.instance.getTotalUsersCount(), Icons.people_outline, AppColors.primary),
                _buildFirestoreStatCard('Pending NFTs', FirestoreService.instance.getPendingNFTsCountStream(), Icons.pending_actions, AppColors.accentOrange),
                _buildFirestoreStatCard('Approved NFTs', FirestoreService.instance.getApprovedNFTsCountStream(), Icons.check_circle_outline, AppColors.success),
                _buildFirestoreStatCard('Active Auctions', FirestoreService.instance.getActiveAuctionsCountStream(), Icons.gavel_outlined, AppColors.frozenBlue),
                _buildFirestoreStatCard('Reported NFTs', FirestoreService.instance.getReportedNFTsCountStream(), Icons.report_problem_outlined, AppColors.danger),
                _buildFirestoreStatCard('Re-Auctions', FirestoreService.instance.getReAuctionRequestsCountStream(), Icons.restore_page_outlined, Colors.deepPurple),
                _buildFirestoreStatCard('Total Bids', FirestoreService.instance.getTotalBidsCountStream(), Icons.how_to_vote_outlined, Colors.purple),
              ];
              
              return ResponsiveLayout(
                mobile: Column(
                  children: statCards
                      .map((card) => Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                            child: card,
                          ))
                      .toList(),
                ),
                tablet: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: statCards[0]),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(child: statCards[1]),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(child: statCards[2]),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(child: statCards[3]),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(child: statCards[4]),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(child: statCards[5]),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(child: statCards[6]),
                        const SizedBox(width: AppSpacing.lg),
                        const Expanded(child: SizedBox()), // Empty slot for grid balance
                      ],
                    ),
                  ],
                ),
                desktop: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: statCards[0]),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(child: statCards[1]),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(child: statCards[2]),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(child: statCards[3]),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(child: statCards[4]),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(child: statCards[5]),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(child: statCards[6]),
                        const SizedBox(width: AppSpacing.lg),
                        const Expanded(child: SizedBox()),
                        const SizedBox(width: AppSpacing.lg),
                        const Expanded(child: SizedBox()),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),

          // Volume Card
          const SizedBox(height: AppSpacing.lg),
          StreamBuilder<double>(
            stream: FirestoreService.instance.getTotalVolumeStream(),
            builder: (context, snapshot) {
              final volume = snapshot.data ?? 0.0;
              return _buildStatCard(
                'Total Volume',
                '${volume.toStringAsFixed(4)} ETH',
                Icons.bar_chart_outlined,
                Colors.amber,
              );
            },
          ),

          const SizedBox(height: AppSpacing.xxl),
          const Text('Recent Pending NFTs', style: AppTextStyles.h2),
          const SizedBox(height: AppSpacing.lg),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: const PendingNftPage(),
          ),
        ],
      ),
    );
  }

  Widget _buildFirestoreStatCard(
    String title,
    Stream<int> countStream,
    IconData icon,
    Color color,
  ) {
    return StreamBuilder<int>(
      stream: countStream,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return _buildStatCard(title, '$count', icon, color);
      },
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.surface, AppColors.surfaceLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Image.asset('assets/images/logo.png', width: 32, height: 32, color: AppColors.primary),
                const SizedBox(width: 12),
                const Text('LEO Admin', style: AppTextStyles.h2),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: ListView.builder(
              itemCount: _menuItems.length,
              itemBuilder: (context, index) {
                final isSelected = _selectedIndex == index;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: isSelected ? Border.all(color: AppColors.primary.withValues(alpha: 0.3)) : Border.all(color: Colors.transparent),
                  ),
                  child: ListTile(
                    leading: Icon(
                      _getMenuIcon(index),
                      color: isSelected ? AppColors.primary : AppColors.textSecondary,
                    ),
                    title: Text(
                      _menuItems[index],
                      style: AppTextStyles.labelLarge.copyWith(
                        color: isSelected ? AppColors.primary : AppColors.textPrimary,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                    onTap: () {
                      setState(() {
                        _selectedIndex = index;
                      });
                      if (!ResponsiveLayout.isDesktop(context) &&
                          Scaffold.of(context).isDrawerOpen) {
                        Navigator.pop(context);
                      }
                    },
                  ),
                );
              },
            ),
          ),
          // Logout button
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await AuthService.instance.signOut();
                },
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Logout'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger.withValues(alpha: 0.15),
                  foregroundColor: AppColors.danger,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: AppColors.primary,
                  child: Icon(Icons.admin_panel_settings, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Admin User', style: AppTextStyles.labelLarge),
                    Text('Superadmin', style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getMenuIcon(int index) {
    switch (index) {
      case 0:
        return Icons.dashboard_outlined;
      case 1:
        return Icons.pending_actions;
      case 2:
        return Icons.check_circle_outline;
      case 3:
        return Icons.gavel_outlined;
      case 4:
        return Icons.people_outline;
      case 5:
        return Icons.report_problem_outlined;
      case 6:
        return Icons.restore_page_outlined;
      default:
        return Icons.circle_outlined;
    }
  }

  Widget _buildHeader() {
    return Builder(builder: (context) {
      bool isDesktop = ResponsiveLayout.isDesktop(context);
      return Container(
        padding: EdgeInsets.symmetric(
            horizontal: !isDesktop ? AppSpacing.lg : AppSpacing.xl, vertical: AppSpacing.lg),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  if (!isDesktop) ...[
                    IconButton(
                      icon: const Icon(Icons.menu, color: AppColors.textPrimary),
                      onPressed: () {
                        Scaffold.of(context).openDrawer();
                      },
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Flexible(
                    child: Text(
                      _menuItems[_selectedIndex],
                      style: AppTextStyles.h2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.notifications_none, color: AppColors.textPrimary),
                ),
                if (isDesktop) const SizedBox(width: AppSpacing.lg),
                if (isDesktop)
                  ElevatedButton.icon(
                    onPressed: () async {
                      await AuthService.instance.signOut();
                    },
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Logout'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.surfaceLight,
                      foregroundColor: AppColors.textPrimary,
                      elevation: 0,
                    ),
                  )
              ],
            )
          ],
        ),
      );
    });
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AppTextStyles.h2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

