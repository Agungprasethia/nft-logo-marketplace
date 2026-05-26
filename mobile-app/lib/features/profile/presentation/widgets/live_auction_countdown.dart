import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';

class LiveAuctionCountdown extends StatefulWidget {
  final DateTime endTime;
  
  const LiveAuctionCountdown({
    super.key,
    required this.endTime,
  });

  @override
  State<LiveAuctionCountdown> createState() => _LiveAuctionCountdownState();
}

class _LiveAuctionCountdownState extends State<LiveAuctionCountdown> {
  Timer? _timer;
  late Duration _timeRemaining;

  @override
  void initState() {
    super.initState();
    _updateTimeRemaining();
    // Update every second only if time is still remaining
    if (_timeRemaining.inSeconds > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _updateTimeRemaining();
            if (_timeRemaining.inSeconds <= 0) {
              _timer?.cancel();
            }
          });
        }
      });
    }
  }

  void _updateTimeRemaining() {
    final now = DateTime.now();
    final difference = widget.endTime.difference(now);
    _timeRemaining = difference.isNegative ? Duration.zero : difference;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _timeRemainingFormatted {
    final d = _timeRemaining;
    if (d == Duration.zero) return 'Ended';
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m ${d.inSeconds % 60}s';
  }

  @override
  Widget build(BuildContext context) {
    final isEnded = _timeRemaining.inSeconds <= 0;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isEnded ? Icons.timer_off_outlined : Icons.timer_outlined,
          size: 14,
          color: isEnded ? AppColors.textSecondary : AppColors.accentOrange,
        ),
        const SizedBox(width: 4),
        Text(
          _timeRemainingFormatted,
          style: AppTextStyles.labelSmall.copyWith(
            color: isEnded ? AppColors.textSecondary : AppColors.accentOrange,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
