import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// /download — dedicated download hub page served at setall.app/download.
/// Fetches the latest GitHub release via API so buttons are always current.
/// Matches the glass-morphism dark aesthetic of the marketing landing page.
class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  static const _kRepo = 'jafanlim/SetAll';
  static const _kBg          = Color(0xFF0F172A);
  static const _kTeal         = Color(0xFF14B8A6);
  static const _kOrange       = Color(0xFFF97316);
  static const _kGlass        = Color(0xFF1E293B);
  static const _kBorder       = Color(0x1AFFFFFF);

  _ReleaseInfo? _release;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchRelease();
  }

  Future<void> _fetchRelease() async {
    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/repos/$_kRepo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final tag     = json['tag_name'] as String? ?? 'latest';
        final assets  = (json['assets'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        final notes   = json['body'] as String? ?? '';

        final downloads = <_DownloadAsset>[];

        for (final a in assets) {
          final name = (a['name'] as String? ?? '').toLowerCase();
          final url  = a['browser_download_url'] as String? ?? '';
          if (url.isEmpty) continue;

          _Platform? platform;
          String? icon;
          if (name.endsWith('.dmg') || name.contains('macos')) {
            platform = _Platform.macOS;
            icon = 'macos';
          } else if (name.endsWith('.exe') || name.contains('windows')) {
            platform = _Platform.windows;
            icon = 'windows';
          } else if (name.endsWith('.apk') || name.contains('android')) {
            platform = _Platform.android;
            icon = 'android';
          } else if (name.contains('linux') || name.endsWith('.deb') || name.endsWith('.appimage')) {
            platform = _Platform.linux;
            icon = 'linux';
          }

          if (platform != null) {
            downloads.add(_DownloadAsset(
              platform: platform,
              icon: icon!,
              url: url,
              filename: a['name'] as String? ?? name,
              sizeMb: ((a['size'] as int? ?? 0) / 1024 / 1024).toStringAsFixed(1),
            ));
          }
        }

        // Sort: macOS → Windows → Android → Linux
        downloads.sort((a, b) => a.platform.index.compareTo(b.platform.index));

        if (mounted) {
          setState(() {
            _release = _ReleaseInfo(tag: tag, assets: downloads, notes: notes);
            _loading = false;
          });
        }
      } else {
        _setFallback();
      }
    } catch (_) {
      _setFallback();
    }
  }

  void _setFallback() {
    if (!mounted) return;
    setState(() {
      _release = _ReleaseInfo(
        tag: 'releases',
        assets: [
          _DownloadAsset(
            platform: _Platform.macOS,
            icon: 'macos',
            url: 'https://github.com/$_kRepo/releases',
            filename: 'View on GitHub Releases',
            sizeMb: '—',
          ),
          _DownloadAsset(
            platform: _Platform.windows,
            icon: 'windows',
            url: 'https://github.com/$_kRepo/releases',
            filename: 'View on GitHub Releases',
            sizeMb: '—',
          ),
          _DownloadAsset(
            platform: _Platform.android,
            icon: 'android',
            url: 'https://github.com/$_kRepo/releases',
            filename: 'View on GitHub Releases',
            sizeMb: '—',
          ),
        ],
        notes: 'No releases published yet. Check back soon or follow the GitHub repository for updates.',
      );
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width    = MediaQuery.of(context).size.width;
    final isMobile = width < 768;

    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          // Ambient glows
          Positioned(
            top: -100, left: -80,
            child: _Orb(size: 400, color: _kTeal.withValues(alpha: 0.15)),
          ),
          Positioned(
            bottom: 0, right: -100,
            child: _Orb(size: 350, color: _kOrange.withValues(alpha: 0.10)),
          ),

          // Content
          SingleChildScrollView(
            child: Column(
              children: [
                _buildNav(isMobile),
                _buildHero(isMobile),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 80),
                    child: CircularProgressIndicator(color: _kTeal),
                  )
                else ...[
                  _buildDownloadGrid(isMobile),
                  _buildStoreSection(isMobile),
                  if (_release?.notes.isNotEmpty == true)
                    _buildReleaseNotes(isMobile),
                ],
                _buildFooter(isMobile),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNav(bool isMobile) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 64,
        vertical: 20,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _launch('https://setall.app'),
            child: const Row(children: [
              Text('⚖️', style: TextStyle(fontSize: 24)),
              SizedBox(width: 8),
              Text('SetAll', style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              )),
            ]),
          ),
          const Spacer(),
          _GlassChip(
            label: _release?.tag ?? '…',
            color: _kTeal,
          ),
        ],
      ),
    );
  }

  Widget _buildHero(bool isMobile) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 24 : 64, 40, isMobile ? 24 : 64, 0,
      ),
      child: Column(
        children: [
          const Text('⚖️', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 20),
          Text(
            'Download SetAll',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: isMobile ? 36 : 52,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              'Premium multi-currency expense sharing. Free forever.\nAvailable on macOS, Windows, Android, iOS & Web.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: isMobile ? 15 : 17,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildDownloadGrid(bool isMobile) {
    final assets = _release?.assets ?? [];
    if (assets.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 64,
        vertical: 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(label: 'Desktop', isMobile: isMobile),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: assets.map((a) => _DownloadCard(
              asset: a,
              isMobile: isMobile,
              onTap: () => _download(a.url, a.filename),
            )).toList(),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildStoreSection(bool isMobile) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 64,
        vertical: 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(label: 'Mobile', isMobile: isMobile),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _StoreCard(
                icon: Icons.apple,
                label: 'App Store',
                subtitle: 'iPhone & iPad',
                color: Colors.white,
                isMobile: isMobile,
                onTap: () => _launch('https://apps.apple.com/app/setall'),
              ),
              _StoreCard(
                icon: Icons.android,
                label: 'Google Play',
                subtitle: 'Android',
                color: const Color(0xFF34A853),
                isMobile: isMobile,
                onTap: () => _launch(
                  'https://play.google.com/store/apps/details?id=com.setall',
                ),
              ),
              _StoreCard(
                icon: Icons.open_in_browser_rounded,
                label: 'Web App',
                subtitle: 'No install needed',
                color: _kTeal,
                isMobile: isMobile,
                onTap: () => _launch('https://app.setall.app'),
              ),
            ],
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildReleaseNotes(bool isMobile) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 64,
        vertical: 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(label: "What's New in ${_release!.tag}", isMobile: isMobile),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 720),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _kGlass.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kBorder),
            ),
            child: Text(
              _release!.notes.length > 800
                  ? '${_release!.notes.substring(0, 800)}…'
                  : _release!.notes,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.70),
                fontSize: 13,
                height: 1.7,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildFooter(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 64,
        vertical: 32,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: _footerContent(isMobile: true),
            )
          : Row(children: _footerContent(isMobile: false)),
    );
  }

  List<Widget> _footerContent({required bool isMobile}) => [
    Text(
      '© ${DateTime.now().year} SetAll App. All rights reserved.',
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.35),
        fontSize: 12,
      ),
    ),
    if (!isMobile) const Spacer(),
    if (isMobile) const SizedBox(height: 12),
    Wrap(
      spacing: 24,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        _FooterLink(label: 'Home',    url: 'https://setall.app'),
        _FooterLink(label: 'Privacy', url: 'https://setall.app/privacy'),
        _FooterLink(label: 'Terms',   url: 'https://setall.app/terms'),
        _FooterLink(label: 'GitHub',  url: 'https://github.com/$_kRepo'),
      ],
    ),
  ];
}

// ── Data models ──────────────────────────────────────────────────────────────

enum _Platform { macOS, windows, android, linux }

class _ReleaseInfo {
  const _ReleaseInfo({
    required this.tag,
    required this.assets,
    this.notes = '',
  });
  final String tag;
  final List<_DownloadAsset> assets;
  final String notes;
}

class _DownloadAsset {
  const _DownloadAsset({
    required this.platform,
    required this.icon,
    required this.url,
    required this.filename,
    required this.sizeMb,
  });
  final _Platform platform;
  final String icon;
  final String url;
  final String filename;
  final String sizeMb;

  String get platformLabel {
    switch (platform) {
      case _Platform.macOS:   return 'macOS';
      case _Platform.windows: return 'Windows';
      case _Platform.android: return 'Android (APK)';
      case _Platform.linux:   return 'Linux';
    }
  }

  IconData get platformIcon {
    switch (platform) {
      case _Platform.macOS:   return Icons.apple;
      case _Platform.windows: return Icons.window_rounded;
      case _Platform.android: return Icons.android;
      case _Platform.linux:   return Icons.terminal;
    }
  }

  Color get platformColor {
    switch (platform) {
      case _Platform.macOS:   return Colors.white;
      case _Platform.windows: return const Color(0xFF00ADEF);
      case _Platform.android: return const Color(0xFF34A853);
      case _Platform.linux:   return const Color(0xFFF97316);
    }
  }
}

// ── Download card ────────────────────────────────────────────────────────────

class _DownloadCard extends StatefulWidget {
  const _DownloadCard({
    required this.asset,
    required this.isMobile,
    required this.onTap,
  });
  final _DownloadAsset asset;
  final bool isMobile;
  final VoidCallback onTap;

  @override
  State<_DownloadCard> createState() => _DownloadCardState();
}

class _DownloadCardState extends State<_DownloadCard> {
  bool _hovered = false;

  static const _kTeal  = Color(0xFF14B8A6);
  static const _kGlass = Color(0xFF1E293B);
  static const _kBorder = Color(0x1AFFFFFF);

  @override
  Widget build(BuildContext context) {
    final a = widget.asset;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: widget.isMobile ? double.infinity : 240,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _hovered
                ? _kGlass.withValues(alpha: 0.9)
                : _kGlass.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _hovered
                  ? a.platformColor.withValues(alpha: 0.5)
                  : _kBorder,
              width: 1,
            ),
            boxShadow: _hovered
                ? [BoxShadow(
                    color: a.platformColor.withValues(alpha: 0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  )]
                : [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: a.platformColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(a.platformIcon, color: a.platformColor, size: 24),
              ),
              const SizedBox(height: 16),
              Text(
                a.platformLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                a.filename,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (a.sizeMb != '—') ...[
                const SizedBox(height: 2),
                Text(
                  '${a.sizeMb} MB',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 11,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(Icons.download_rounded, color: _kTeal, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Download',
                    style: TextStyle(
                      color: _kTeal,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: _kTeal.withValues(alpha: 0.6),
                    size: 12,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Store card ───────────────────────────────────────────────────────────────

class _StoreCard extends StatefulWidget {
  const _StoreCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.isMobile,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final bool isMobile;
  final VoidCallback onTap;

  @override
  State<_StoreCard> createState() => _StoreCardState();
}

class _StoreCardState extends State<_StoreCard> {
  bool _hovered = false;

  static const _kGlass  = Color(0xFF1E293B);
  static const _kBorder = Color(0x1AFFFFFF);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: widget.isMobile ? double.infinity : 200,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _hovered
                ? _kGlass.withValues(alpha: 0.9)
                : _kGlass.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hovered
                  ? widget.color.withValues(alpha: 0.4)
                  : _kBorder,
            ),
          ),
          child: Row(
            children: [
              Icon(widget.icon, color: widget.color, size: 28),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.label, style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  )),
                  Text(widget.subtitle, style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11,
                  )),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared helpers ───────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.isMobile});
  final String label;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF14B8A6),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
      ),
    );
  }
}

class _GlassChip extends StatelessWidget {
  const _GlassChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(
        color: color, fontSize: 12, fontWeight: FontWeight.w600,
      )),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label, required this.url});
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _launch(url),
      child: Text(label, style: TextStyle(
        color: Colors.white.withValues(alpha: 0.35),
        fontSize: 12,
      )),
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, Colors.transparent]),
      ),
    );
  }
}

Future<void> _launch(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Opens the download URL in the browser/system handler.
void _download(String url, String filename) {
  _launch(url);
}
