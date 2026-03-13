import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Renders a legal document (Privacy Policy or Terms of Service) loaded from
/// assets/legal/*.md. Matches the glass-morphism dark aesthetic.
class LegalScreen extends StatefulWidget {
  const LegalScreen({super.key, required this.title, required this.assetPath});

  final String title;
  final String assetPath;

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  static const _kBg     = Color(0xFF0F172A);
  static const _kTeal   = Color(0xFF14B8A6);
  static const _kGlass  = Color(0xFF1E293B);
  static const _kBorder = Color(0x1AFFFFFF);

  String? _content;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    try {
      final text = await rootBundle.loadString(widget.assetPath);
      if (mounted) setState(() { _content = text; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _content = 'Document not available.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final width    = MediaQuery.of(context).size.width;
    final isMobile = width < 768;

    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          // Ambient glow
          Positioned(
            top: -80, left: -60,
            child: _buildOrb(360, _kTeal.withValues(alpha: 0.10)),
          ),

          SingleChildScrollView(
            child: Column(
              children: [
                _buildNav(isMobile),
                _buildContent(isMobile),
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
            onTap: () => Navigator.of(context).maybePop(),
            child: Row(children: [
              Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white.withValues(alpha: 0.6), size: 16),
              const SizedBox(width: 8),
              const Text('SetAll', style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              )),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(bool isMobile) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 64,
        vertical: 8,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Text(
                widget.title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isMobile ? 32 : 44,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 32),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 80),
                    child: CircularProgressIndicator(color: _kTeal),
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: _kGlass.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _kBorder),
                  ),
                  child: _MarkdownText(content: _content ?? ''),
                ),
              const SizedBox(height: 64),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 64,
        vertical: 28,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '© ${DateTime.now().year} SetAll App.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 12,
            ),
          ),
          Text(
            'setall.app',
            style: TextStyle(
              color: _kTeal.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrb(double size, Color color) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, Colors.transparent]),
      ),
    );
  }
}

// ── Minimal markdown renderer ─────────────────────────────────────────────────
// Parses headings (##, ###), bold (**text**), horizontal rules (---), and plain text.
// Avoids adding a heavy dependency for a simple legal doc.

class _MarkdownText extends StatelessWidget {
  const _MarkdownText({required this.content});
  final String content;

  static const _kText    = Color(0xFFCDD6E0);
  static const _kTeal    = Color(0xFF14B8A6);
  static const _kBorder  = Color(0x1AFFFFFF);

  @override
  Widget build(BuildContext context) {
    final lines = content.split('\n');
    final widgets = <Widget>[];

    for (final rawLine in lines) {
      final line = rawLine.trimRight();

      if (line.startsWith('# ')) {
        widgets.add(_heading(line.substring(2), 22, Colors.white));
      } else if (line.startsWith('## ')) {
        widgets.add(const SizedBox(height: 20));
        widgets.add(_heading(line.substring(3), 17, _kTeal));
        widgets.add(Container(height: 1, color: _kBorder, margin: const EdgeInsets.only(top: 6, bottom: 4)));
      } else if (line.startsWith('### ')) {
        widgets.add(const SizedBox(height: 8));
        widgets.add(_heading(line.substring(4), 14, Colors.white));
      } else if (line.startsWith('---')) {
        widgets.add(Container(height: 1, color: _kBorder, margin: const EdgeInsets.symmetric(vertical: 12)));
      } else if (line.startsWith('- ')) {
        widgets.add(_bulletLine(line.substring(2)));
      } else if (line.isEmpty) {
        widgets.add(const SizedBox(height: 8));
      } else {
        widgets.add(_paragraph(line));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _heading(String text, double size, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: TextStyle(
        color: color, fontSize: size, fontWeight: FontWeight.w700, height: 1.3,
      )),
    );
  }

  Widget _bulletLine(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Container(
              width: 4, height: 4,
              decoration: const BoxDecoration(
                color: _kTeal,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(child: _richText(text, 13)),
        ],
      ),
    );
  }

  Widget _paragraph(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: _richText(text, 13),
    );
  }

  Widget _richText(String text, double fontSize) {
    // Parse **bold** spans
    final spans = <TextSpan>[];
    final boldRe = RegExp(r'\*\*(.*?)\*\*');
    int cursor = 0;

    for (final m in boldRe.allMatches(text)) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, m.start)));
      }
      spans.add(TextSpan(
        text: m.group(1),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ));
      cursor = m.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(
          color: _kText,
          fontSize: fontSize,
          height: 1.65,
        ),
        children: spans,
      ),
    );
  }
}
