import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Premium marketing landing page served at setall.app via Firebase Hosting.
/// Rendered only on web (kIsWeb). Uses a single scrollable column with
/// a sticky header, hero, feature grid, social proof, and CTA footer.
class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final _scroll = ScrollController();
  bool _headerElevated = false;

  static const _kBg         = Color(0xFF0A0A0E);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final elevated = _scroll.offset > 10;
      if (elevated != _headerElevated) setState(() => _headerElevated = elevated);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 768;

    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          // ── Ambient gradient orbs ──────────────────────────────────────
          Positioned(top: -120, left: -80, child: _Orb(size: 480, color: const Color(0x0FD4AF37))),
          Positioned(top: 300, right: -100, child: _Orb(size: 360, color: const Color(0x0D3B82F6))),
          Positioned(bottom: 200, left: -60, child: _Orb(size: 300, color: const Color(0x0AD4AF37))),

          // ── Scrollable content ────────────────────────────────────────
          CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(child: _HeroSection(isMobile: isMobile)),
              SliverToBoxAdapter(child: _TrustBar(isMobile: isMobile)),
              SliverToBoxAdapter(child: _FeatureGrid(isMobile: isMobile)),
              SliverToBoxAdapter(child: _HowItWorks(isMobile: isMobile)),
              SliverToBoxAdapter(child: _SocialProof(isMobile: isMobile)),
              SliverToBoxAdapter(child: _CtaSection(isMobile: isMobile)),
              SliverToBoxAdapter(child: _Footer(isMobile: isMobile)),
            ],
          ),

          // ── Sticky header ──────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: _Header(elevated: _headerElevated, isMobile: isMobile),
          ),
        ],
      ),
    );
  }
}

// ── Header ─────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.elevated, required this.isMobile});
  final bool elevated;
  final bool isMobile;

  static const _kGold    = Color(0xFFD4AF37);
  static const _kBg      = Color(0xFF0A0A0E);
  static const _kText    = Color(0xFFE8E8EC);

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      color: elevated
          ? _kBg.withValues(alpha: 0.92)
          : Colors.transparent,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 64,
        vertical: 16,
      ),
      child: Row(
        children: [
          // Logo
          Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: _kGold,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text('S', style: TextStyle(
                  color: Color(0xFF0A0A0E),
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                )),
              ),
            ),
            const SizedBox(width: 10),
            const Text('SetAll', style: TextStyle(
              color: _kText,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            )),
          ]),
          const Spacer(),
          if (!isMobile) ...[
            _NavLink(label: 'Features', onTap: () {}),
            const SizedBox(width: 32),
            _NavLink(label: 'Pricing', onTap: () {}),
            const SizedBox(width: 32),
            _NavLink(label: 'About', onTap: () {}),
            const SizedBox(width: 40),
          ],
          _GoldButton(
            label: isMobile ? 'Download' : 'Download Free',
            small: true,
            onTap: () => _launch('https://setall.app/download'),
          ),
        ],
      ),
    );
  }
}

class _NavLink extends StatelessWidget {
  const _NavLink({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(label, style: const TextStyle(
        color: Color(0xFF8A8A96), fontSize: 14, fontWeight: FontWeight.w500,
      )),
    );
  }
}

// ── Hero ────────────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.isMobile});
  final bool isMobile;

  static const _kGold      = Color(0xFFD4AF37);
  static const _kGoldLight = Color(0xFFF0D060);
  static const _kText      = Color(0xFFE8E8EC);
  static const _kMuted     = Color(0xFF8A8A96);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 24 : 64, 120, isMobile ? 24 : 64, 80,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: _kGold.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(100),
              color: _kGold.withValues(alpha: 0.08),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, color: _kGold, size: 14),
                SizedBox(width: 6),
                Text('Now with real-time sync', style: TextStyle(
                  color: _kGold, fontSize: 12, fontWeight: FontWeight.w600,
                )),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Headline
          Text(
            'Split expenses.\nSettle smarter.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _kText,
              fontSize: isMobile ? 40 : 72,
              fontWeight: FontWeight.w800,
              height: 1.1,
              letterSpacing: -2,
            ),
          ),
          const SizedBox(height: 8),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [_kGold, _kGoldLight],
            ).createShader(bounds),
            child: Text(
              'No stress. Just SetAll.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: isMobile ? 40 : 72,
                fontWeight: FontWeight.w800,
                height: 1.1,
                letterSpacing: -2,
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Sub-headline
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(
              'The premium group expense tracker built for friends, flatmates, and couples. '
              'Track in any currency, settle instantly, and sleep easy.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _kMuted,
                fontSize: isMobile ? 16 : 18,
                height: 1.6,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(height: 44),

          // CTA buttons
          Wrap(
            spacing: 16, runSpacing: 16,
            alignment: WrapAlignment.center,
            children: [
              _GoldButton(
                label: 'Download for Free',
                onTap: () => _launch('https://setall.app/download'),
              ),
              _OutlineButton(
                label: 'View on GitHub',
                icon: Icons.code,
                onTap: () => _launch('https://github.com/shoko12/setall'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'iOS · Android · macOS · Windows · Web',
            style: TextStyle(color: _kMuted.withValues(alpha: 0.6), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ── Trust bar ───────────────────────────────────────────────────────────────

class _TrustBar extends StatelessWidget {
  const _TrustBar({required this.isMobile});
  final bool isMobile;

  static const _kBorder = Color(0xFF2A2A35);
  static const _kMuted  = Color(0xFF8A8A96);
  static const _kGold   = Color(0xFFD4AF37);

  static const _items = [
    ('50+ currencies', Icons.currency_exchange),
    ('Offline-first', Icons.offline_bolt),
    ('End-to-end sync', Icons.sync),
    ('No ads ever', Icons.block),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0),
      padding: EdgeInsets.symmetric(
        vertical: 20, horizontal: isMobile ? 24 : 64,
      ),
      decoration: const BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: _kBorder),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceEvenly,
        runSpacing: 16,
        children: _items.map((item) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.$2, color: _kGold, size: 16),
              const SizedBox(width: 8),
              Text(item.$1, style: const TextStyle(
                color: _kMuted, fontSize: 13, fontWeight: FontWeight.w500,
              )),
            ],
          ),
        )).toList(),
      ),
    );
  }
}

// ── Feature grid ────────────────────────────────────────────────────────────

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid({required this.isMobile});
  final bool isMobile;

  static const _features = [
    _Feature(
      icon: Icons.groups_rounded,
      color: Color(0xFFD4AF37),
      title: 'Smart Group Splits',
      body: 'Create groups, add expenses, and let SetAll calculate who owes what — instantly, with zero ambiguity.',
    ),
    _Feature(
      icon: Icons.currency_exchange_rounded,
      color: Color(0xFF38BDF8),
      title: 'Multi-Currency',
      body: 'Travel together without currency headaches. SetAll fetches live rates and converts automatically.',
    ),
    _Feature(
      icon: Icons.account_balance_wallet_rounded,
      color: Color(0xFF4ADE80),
      title: 'Personal Wallet',
      body: 'Track your own income and expenses separately. Complete financial picture, one app.',
    ),
    _Feature(
      icon: Icons.offline_bolt_rounded,
      color: Color(0xFFA78BFA),
      title: 'Offline First',
      body: 'No signal? No problem. All data lives on your device first, synced to the cloud when you reconnect.',
    ),
    _Feature(
      icon: Icons.notifications_active_rounded,
      color: Color(0xFFF97316),
      title: 'Push Notifications',
      body: 'Get instant alerts when a friend adds an expense or settles a debt — powered by Firebase.',
    ),
    _Feature(
      icon: Icons.lock_rounded,
      color: Color(0xFFEC4899),
      title: 'Biometric Security',
      body: 'Face ID and Touch ID support keeps your financial data safe from prying eyes.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final crossCount = isMobile ? 1 : 3;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 64, vertical: 80,
      ),
      child: Column(
        children: [
          _SectionLabel(label: 'Features'),
          const SizedBox(height: 16),
          _SectionHeadline(
            text: 'Everything you need.\nNothing you don\'t.',
            isMobile: isMobile,
          ),
          const SizedBox(height: 56),
          GridView.count(
            crossAxisCount: crossCount,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: isMobile ? 3.2 : 1.55,
            children: _features.map((f) => _FeatureCard(feature: f)).toList(),
          ),
        ],
      ),
    );
  }
}

class _Feature {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  const _Feature({required this.icon, required this.color, required this.title, required this.body});
}

class _FeatureCard extends StatefulWidget {
  const _FeatureCard({required this.feature});
  final _Feature feature;

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _hovered = false;

  static const _kCard   = Color(0xFF18181F);
  static const _kBorder = Color(0xFF2A2A35);
  static const _kText   = Color(0xFFE8E8EC);
  static const _kMuted  = Color(0xFF8A8A96);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _hovered
              ? widget.feature.color.withValues(alpha: 0.06)
              : _kCard,
          border: Border.all(
            color: _hovered
                ? widget.feature.color.withValues(alpha: 0.35)
                : _kBorder,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: widget.feature.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(widget.feature.icon, color: widget.feature.color, size: 20),
            ),
            const SizedBox(height: 16),
            Text(widget.feature.title, style: const TextStyle(
              color: _kText, fontSize: 15, fontWeight: FontWeight.w700,
            )),
            const SizedBox(height: 8),
            Expanded(
              child: Text(widget.feature.body, style: const TextStyle(
                color: _kMuted, fontSize: 13, height: 1.5,
              )),
            ),
          ],
        ),
      ),
    );
  }
}

// ── How it works ────────────────────────────────────────────────────────────

class _HowItWorks extends StatelessWidget {
  const _HowItWorks({required this.isMobile});
  final bool isMobile;

  static const _steps = [
    ('Create a group', 'Name your trip, household, or event. Invite friends with a link.', Icons.add_circle_outline),
    ('Add expenses', 'Snap a receipt or type it in. SetAll splits it instantly.', Icons.receipt_long_rounded),
    ('Settle up', 'See exactly who owes whom. One tap to mark as settled.', Icons.check_circle_outline),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111118),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 64, vertical: 80,
      ),
      child: Column(
        children: [
          _SectionLabel(label: 'How it works'),
          const SizedBox(height: 16),
          _SectionHeadline(text: 'Up and running in\nunder 60 seconds.', isMobile: isMobile),
          const SizedBox(height: 56),
          isMobile
              ? Column(
                  children: _buildSteps(),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _buildStepsWithDividers(),
                ),
        ],
      ),
    );
  }

  List<Widget> _buildSteps() => List.generate(_steps.length, (i) {
    final step = _steps[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: _StepCard(index: i + 1, step: step),
    );
  });

  List<Widget> _buildStepsWithDividers() {
    final items = <Widget>[];
    for (int i = 0; i < _steps.length; i++) {
      items.add(Expanded(child: _StepCard(index: i + 1, step: _steps[i])));
      if (i < _steps.length - 1) {
        items.add(Container(
          width: 1, height: 60, margin: const EdgeInsets.symmetric(horizontal: 16),
          color: const Color(0xFF2A2A35),
        ));
      }
    }
    return items;
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.index, required this.step});
  final int index;
  final (String, String, IconData) step;

  static const _kText  = Color(0xFFE8E8EC);
  static const _kMuted = Color(0xFF8A8A96);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.4)),
              ),
              child: Center(
                child: Text('$index', style: const TextStyle(
                  color: Color(0xFFD4AF37), fontWeight: FontWeight.w800, fontSize: 14,
                )),
              ),
            ),
            const SizedBox(width: 12),
            Icon(step.$3, color: const Color(0xFFD4AF37), size: 20),
          ]),
          const SizedBox(height: 16),
          Text(step.$1, style: const TextStyle(
            color: _kText, fontSize: 16, fontWeight: FontWeight.w700,
          )),
          const SizedBox(height: 8),
          Text(step.$2, style: const TextStyle(
            color: _kMuted, fontSize: 13, height: 1.5,
          )),
        ],
      ),
    );
  }
}

// ── Social proof ────────────────────────────────────────────────────────────

class _SocialProof extends StatelessWidget {
  const _SocialProof({required this.isMobile});
  final bool isMobile;

  static const _reviews = [
    _Review('Finally an app that gets it. No upsells, no subscription nonsense. Just clean, fast expense splitting.', 'Alex T.', 'Product designer'),
    _Review('The multi-currency support is a game changer for our international friend group. Absolutely love SetAll.', 'Priya M.', 'Frequent traveller'),
    _Review('Works offline, syncs when I\'m back on WiFi. My flatmates and I use it every single day.', 'James K.', 'Software engineer'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 64, vertical: 80,
      ),
      child: Column(
        children: [
          _SectionLabel(label: 'Reviews'),
          const SizedBox(height: 16),
          _SectionHeadline(text: 'Loved by users\naround the world.', isMobile: isMobile),
          const SizedBox(height: 56),
          isMobile
              ? Column(children: _reviews.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _ReviewCard(review: r),
                )).toList())
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _reviews.map((r) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _ReviewCard(review: r),
                    ),
                  )).toList(),
                ),
        ],
      ),
    );
  }
}

class _Review {
  final String quote;
  final String name;
  final String title;
  const _Review(this.quote, this.name, this.title);
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});
  final _Review review;

  static const _kCard   = Color(0xFF18181F);
  static const _kBorder = Color(0xFF2A2A35);
  static const _kText   = Color(0xFFE8E8EC);
  static const _kMuted  = Color(0xFF8A8A96);
  static const _kGold   = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _kCard,
        border: Border.all(color: _kBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: List.generate(5, (_) => const Padding(
            padding: EdgeInsets.only(right: 3),
            child: Icon(Icons.star_rounded, color: _kGold, size: 14),
          ))),
          const SizedBox(height: 16),
          Text('"${review.quote}"', style: const TextStyle(
            color: _kText, fontSize: 14, height: 1.6, fontStyle: FontStyle.italic,
          )),
          const SizedBox(height: 20),
          Text(review.name, style: const TextStyle(
            color: _kText, fontWeight: FontWeight.w700, fontSize: 13,
          )),
          Text(review.title, style: const TextStyle(
            color: _kMuted, fontSize: 12,
          )),
        ],
      ),
    );
  }
}

class _CtaSection extends StatelessWidget {
  const _CtaSection({required this.isMobile});
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111118),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 64, vertical: 80,
      ),
      child: Column(
        children: [
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [Color(0xFFD4AF37), Color(0xFFF0D060)],
            ).createShader(b),
            child: Text(
              'Ready to SetAll?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: isMobile ? 36 : 56,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.5,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Free forever. No credit card. No catch.',
            style: const TextStyle(color: Color(0xFF8A8A96), fontSize: 15),
          ),
          const SizedBox(height: 40),
          Wrap(
            spacing: 16, runSpacing: 16,
            alignment: WrapAlignment.center,
            children: [
              _GoldButton(
                label: 'Download for iOS',
                icon: Icons.apple,
                onTap: () => _launch('https://apps.apple.com/app/setall'),
              ),
              _GoldButton(
                label: 'Download for Android',
                icon: Icons.android,
                onTap: () => _launch('https://play.google.com/store/apps/details?id=com.setall'),
              ),
              _OutlineButton(
                label: 'Open Web App',
                icon: Icons.open_in_browser_rounded,
                onTap: () => _launch('https://app.setall.app'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Footer ───────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer({required this.isMobile});
  final bool isMobile;

  static const _kBorder = Color(0xFF2A2A35);
  static const _kMuted  = Color(0xFF8A8A96);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 64, vertical: 32,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _kBorder)),
      ),
      child: isMobile
          ? Column(crossAxisAlignment: CrossAxisAlignment.center, children: _buildContent(isMobile: true))
          : Row(children: _buildContent(isMobile: false)),
    );
  }

  List<Widget> _buildContent({required bool isMobile}) => [
    Text('© ${DateTime.now().year} SetAll. Built with ♥',
      style: const TextStyle(color: _kMuted, fontSize: 12)),
    if (!isMobile) const Spacer(),
    if (isMobile) const SizedBox(height: 16),
    Wrap(
      spacing: 24, runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        _FooterLink(label: 'Privacy', url: 'https://setall.app/privacy'),
        _FooterLink(label: 'Terms',   url: 'https://setall.app/terms'),
        _FooterLink(label: 'GitHub',  url: 'https://github.com/shoko12/setall'),
      ],
    ),
  ];
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label, required this.url});
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _launch(url),
      child: Text(label, style: const TextStyle(
        color: Color(0xFF8A8A96), fontSize: 12,
        decoration: TextDecoration.none,
      )),
    );
  }
}

// ── Shared helper widgets ────────────────────────────────────────────────────

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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(100),
        color: const Color(0xFFD4AF37).withValues(alpha: 0.06),
      ),
      child: Text(label.toUpperCase(), style: const TextStyle(
        color: Color(0xFFD4AF37), fontSize: 11,
        fontWeight: FontWeight.w700, letterSpacing: 1.5,
      )),
    );
  }
}

class _SectionHeadline extends StatelessWidget {
  const _SectionHeadline({required this.text, required this.isMobile});
  final String text;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: const Color(0xFFE8E8EC),
        fontSize: isMobile ? 32 : 48,
        fontWeight: FontWeight.w800,
        height: 1.15,
        letterSpacing: -1,
      ),
    );
  }
}

class _GoldButton extends StatefulWidget {
  const _GoldButton({required this.label, this.icon, required this.onTap, this.small = false});
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool small;

  @override
  State<_GoldButton> createState() => _GoldButtonState();
}

class _GoldButtonState extends State<_GoldButton> {
  bool _hovered = false;

  static const _kGold      = Color(0xFFD4AF37);
  static const _kGoldLight = Color(0xFFF0D060);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: widget.small
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
              : const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              _hovered ? _kGoldLight : _kGold,
              _hovered ? _kGold : const Color(0xFFA88B2A),
            ]),
            borderRadius: BorderRadius.circular(widget.small ? 8 : 12),
            boxShadow: _hovered
                ? [BoxShadow(color: _kGold.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 4))]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: const Color(0xFF0A0A0E), size: widget.small ? 14 : 18),
                const SizedBox(width: 8),
              ],
              Text(widget.label, style: TextStyle(
                color: const Color(0xFF0A0A0E),
                fontWeight: FontWeight.w700,
                fontSize: widget.small ? 13 : 15,
              )),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatefulWidget {
  const _OutlineButton({required this.label, this.icon, required this.onTap});
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  State<_OutlineButton> createState() => _OutlineButtonState();
}

class _OutlineButtonState extends State<_OutlineButton> {
  bool _hovered = false;

  static const _kBorder = Color(0xFF3A3A45);
  static const _kText   = Color(0xFFE8E8EC);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFF2A2A35) : Colors.transparent,
            border: Border.all(color: _hovered ? const Color(0xFF4A4A55) : _kBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: _kText, size: 18),
                const SizedBox(width: 8),
              ],
              Text(widget.label, style: const TextStyle(
                color: _kText, fontWeight: FontWeight.w600, fontSize: 15,
              )),
            ],
          ),
        ),
      ),
    );
  }
}

// ── URL helper ───────────────────────────────────────────────────────────────

Future<void> _launch(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) await launchUrl(uri);
}
