import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart' show Share;

import '../../../core/utils/amount_formatter.dart';

// TODO(FEAT-03-P2): handle incoming setall://settle in app router

/// Bottom sheet that displays a QR code encoding a deep-link settle request.
///
/// Deep-link format:
///   setall://settle?group=G&from=F&to=T&amount=A&currency=C
class SettleQrSheet extends StatelessWidget {
  const SettleQrSheet({
    super.key,
    required this.groupId,
    required this.fromUserId,
    required this.toUserId,
    required this.amount,
    required this.currency,
  });

  final String groupId;
  final String fromUserId;
  final String toUserId;
  final Decimal amount;
  final String currency;

  String get _deepLink {
    final a = formatAmount(amount.toString());
    return 'setall://settle?group=$groupId&from=$fromUserId&to=$toUserId'
        '&amount=$a&currency=$currency';
  }

  String get _displayAmount => '$currency ${formatAmount(amount.toString())}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deepLink = _deepLink;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.4,
      maxChildSize: 0.75,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  'Settle Up',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  _displayAmount,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF14B8A6),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    data: deepLink,
                    size: 220,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF14B8A6),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  'Ask the other person to scan this code',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: () {
                  Share.share(deepLink);
                },
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share Link'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF14B8A6),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
