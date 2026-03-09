import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/haptic_utils.dart';

const _teal  = Color(0xFF00D9B0);
const _slate = Color(0xFF94A3B8);

class InviteFriendScreen extends ConsumerStatefulWidget {
  const InviteFriendScreen({super.key});

  @override
  ConsumerState<InviteFriendScreen> createState() => _InviteFriendScreenState();
}

class _InviteFriendScreenState extends ConsumerState<InviteFriendScreen> {
  final _shareKey = GlobalKey();

  Rect? _shareButtonRect() {
    final box = _shareKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final pos = box.localToGlobal(Offset.zero);
    return pos & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final uid    = ref.watch(currentUserIdProvider) ?? '';
    final link   = 'https://setall.app/join/$uid';
    final shareText =
        'Join me on SetAll to track our shared expenses: $link';

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Invite a Friend',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: -0.3,
          ),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Hero icon ──────────────────────────────────────────────────
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: _teal.withAlpha(30),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(Icons.person_add_outlined,
                    size: 36, color: _teal),
              ),
            ),
            const SizedBox(height: 20),

            // ── Headline ───────────────────────────────────────────────────
            Text(
              'Share your personal link',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Anyone who joins via your link will be automatically connected to you on SetAll.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _slate,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),

            // ── Link card ──────────────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withAlpha(120),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded, size: 18, color: _teal),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      link,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: theme.colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Copy button ────────────────────────────────────────────────
            OutlinedButton.icon(
              onPressed: () async {
                HapticUtils.success();
                await Clipboard.setData(ClipboardData(text: link));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    SnackBar(
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                      backgroundColor: _teal,
                      content: Row(
                        children: [
                          const Icon(Icons.check_circle_outline,
                              color: Colors.black, size: 18),
                          const SizedBox(width: 10),
                          Text(
                            'Link copied!',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.black,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy link'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _teal,
                side: const BorderSide(color: _teal, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),

            // ── Share button ───────────────────────────────────────────────
            FilledButton.icon(
              key: _shareKey,
              onPressed: () {
                HapticUtils.primaryTap();
                final rect = _shareButtonRect();
                Share.share(
                  shareText,
                  subject: 'Join me on SetAll',
                  sharePositionOrigin: rect ?? const Rect.fromLTWH(0, 0, 1, 1),
                );
              },
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              label: const Text('Share via…'),
              style: FilledButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),

            const Spacer(),

            // ── Footer note ────────────────────────────────────────────────
            Text(
              'Your link is unique to your account and never expires.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: _slate, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
