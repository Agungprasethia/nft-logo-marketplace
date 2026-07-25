import 'package:flutter/material.dart';

class LogoDetailPage extends StatefulWidget {
  const LogoDetailPage({super.key});

  @override
  State<LogoDetailPage> createState() => _LogoDetailPageState();
}

class _LogoDetailPageState extends State<LogoDetailPage> {
  // Colors based on the specification
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color successGreen = Color(0xFF22C55E);
  static const Color dangerRed = Color(0xFFEF4444);
  
  @override
  Widget build(BuildContext context) {
    // Determine if the current theme is dark mode
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    // Theme-dependent colors
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF9FAFB);
    final cardColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF111827);
    final textSecondaryColor = isDarkMode ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final borderColor = isDarkMode ? const Color(0xFF374151) : const Color(0xFFE5E7EB);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Logo Detail',
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.share_outlined, color: textColor),
            onPressed: () {},
          ),

        ],
      ),
      body: RefreshIndicator(
      onRefresh: () async { if (mounted) setState(() {}); },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section 2: Logo Preview
              _buildLogoPreview(cardColor),
              const SizedBox(height: 24),

              // Section 3: Logo Info
              _buildLogoInfo(textColor, primaryBlue),
              const SizedBox(height: 20),

              // Section 4: Auction Status
              _buildAuctionStatus(successGreen, textColor, textSecondaryColor, borderColor),
              const SizedBox(height: 24),

              // Section 5: Description
              _buildDescription(textSecondaryColor),
              const SizedBox(height: 24),

              // Section 6: Highest Bid
              _buildHighestBid(cardColor, textColor, textSecondaryColor, borderColor),
              const SizedBox(height: 24),

              // Section 7: Place Bid Button
              _buildPlaceBidButton(textSecondaryColor),
              const SizedBox(height: 32),

              // Section 8: Top Bidders List
              _buildTopBidders(textColor, textSecondaryColor, primaryBlue),
              const SizedBox(height: 32),

              // Section 9: Report Button
              _buildReportButton(dangerRed),
              const SizedBox(height: 24),
              
              // Note Section
              _buildNoteSection(primaryBlue),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildLogoPreview(Color cardColor) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          height: 260,
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A), // Dark/black background for logo
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Placeholder for actual Logo Image
                Icon(
                  Icons.change_history,
                  size: 100,
                  color: Colors.amber.shade300,
                ),
                Positioned(
                  bottom: 30,
                  child: Text(
                    'N E X O R A',
                    style: TextStyle(
                      color: Colors.amber.shade300,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Pagination dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: primaryBlue,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLogoInfo(Color textColor, Color primaryBlue) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Nexora Logo',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.verified, color: primaryBlue, size: 24),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              'by ',
              style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 14),
            ),
            Text(
              '0xA1B2...C3D4',
              style: TextStyle(
                color: primaryBlue,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.verified_user, color: primaryBlue, size: 16),
            const SizedBox(width: 4),
            Text(
              'Verified Creator',
              style: TextStyle(
                color: primaryBlue,
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAuctionStatus(Color successGreen, Color textColor, Color textSecondaryColor, Color borderColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Auction Live Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: successGreen.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: successGreen.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: successGreen,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Auction Live',
                style: TextStyle(
                  color: successGreen,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        
        // Countdown Timer
        Row(
          children: [
            Text(
              'Ends in',
              style: TextStyle(
                color: textSecondaryColor,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 8),
            _buildTimeBox('02', 'D', textColor, textSecondaryColor, borderColor),
            const SizedBox(width: 4),
            Text(':', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            _buildTimeBox('15', 'H', textColor, textSecondaryColor, borderColor),
            const SizedBox(width: 4),
            Text(':', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            _buildTimeBox('47', 'M', textColor, textSecondaryColor, borderColor),
            const SizedBox(width: 4),
            Text(':', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            _buildTimeBox('36', 'S', textColor, textSecondaryColor, borderColor),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeBox(String time, String label, Color textColor, Color textSecondaryColor, Color borderColor) {
    return Column(
      children: [
        Text(
          time,
          style: TextStyle(
            color: primaryBlue,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: textSecondaryColor,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildDescription(Color textSecondaryColor) {
    return Text(
      'Modern and minimalist logo design for Nexora brand. This logo represents innovation, growth, and forward thinking. Suitable for technology, finance, and startup company.',
      style: TextStyle(
        color: textSecondaryColor,
        height: 1.5,
        fontSize: 14,
      ),
    );
  }

  Widget _buildHighestBid(Color cardColor, Color textColor, Color textSecondaryColor, Color borderColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current Highest Bid',
            style: TextStyle(
              color: textSecondaryColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '1.250 ETH',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '≈ \$2,450.75',
                    style: TextStyle(
                      color: textSecondaryColor,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Text(
                    'by 0xF5E6...A7B8',
                    style: TextStyle(
                      color: textSecondaryColor,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('👑', style: TextStyle(fontSize: 16)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceBidButton(Color textSecondaryColor) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.gavel),
                SizedBox(width: 8),
                Text(
                  'Place a Bid',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 14, color: primaryBlue),
            const SizedBox(width: 6),
            Text(
              'All bids are secured by smart contract',
              style: TextStyle(
                color: textSecondaryColor,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTopBidders(Color textColor, Color textSecondaryColor, Color primaryBlue) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Top Bidders',
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton(
              onPressed: () {},
              child: Text(
                'View All',
                style: TextStyle(
                  color: primaryBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildBidderRow(1, '0xF5E6...A7B8', '1.250 ETH', Colors.amber, textColor),
        _buildBidderRow(2, '0x9A8B...C1D2', '1.000 ETH', Colors.blueGrey, textColor),
        _buildBidderRow(3, '0x7C3D...E4F5', '0.750 ETH', Colors.brown.shade400, textColor),
        _buildBidderRow(4, '0x1A2B...3C4D', '0.500 ETH', Colors.grey.shade400, textColor),
        _buildBidderRow(5, '0x8D9E...F0A1', '0.300 ETH', Colors.grey.shade400, textColor),
      ],
    );
  }

  Widget _buildBidderRow(int rank, String wallet, String amount, Color rankColor, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          // Rank circle
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: rankColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                rank.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Avatar
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Icon(Icons.person, size: 20, color: Colors.grey.shade500),
          ),
          const SizedBox(width: 12),
          // Wallet
          Text(
            wallet,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          // Amount
          Text(
            amount,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportButton(Color dangerRed) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: () {},
        style: OutlinedButton.styleFrom(
          foregroundColor: dangerRed,
          side: BorderSide(color: dangerRed),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.flag_outlined),
            SizedBox(width: 8),
            Text(
              'Report This Logo',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildNoteSection(Color primaryBlue) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: primaryBlue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryBlue.withValues(alpha: 0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info, color: primaryBlue, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Catatan',
                  style: TextStyle(
                    color: primaryBlue,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Semua data lelang dan kepemilikan tercatat di blockchain secara transparan dan tidak dapat diubah.',
                  style: TextStyle(
                    color: primaryBlue,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
