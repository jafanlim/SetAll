import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/services/date_format_service.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';

const _kRegionChannel = MethodChannel('com.setall.app/region');

const _teal  = Color(0xFF00D9B0);
const _slate = Color(0xFF94A3B8);

// ---------------------------------------------------------------------------
// Prefs keys
// ---------------------------------------------------------------------------
const _kDateFmtKey   = 'regional_date_format';
const _kManualFmt    = 'regional_manual_override';

const _kFmtDMY  = 'DD/MM/YYYY';
const _kFmtMDY  = 'MM/DD/YYYY';
const _kFmtYMD  = 'YYYY-MM-DD';

// ---------------------------------------------------------------------------
// RegionalScreen
// ---------------------------------------------------------------------------
class RegionalScreen extends StatefulWidget {
  const RegionalScreen({super.key});

  @override
  State<RegionalScreen> createState() => _RegionalScreenState();
}

class _RegionalScreenState extends State<RegionalScreen> {
  bool   _manualOverride  = false;
  String _dateFormat      = _kFmtDMY;
  bool   _loading         = true;
  // Resolved region locale string — on macOS comes from platform channel
  // (Locale.current.identifier = region locale); other platforms use language locale.
  String _regionLocaleStr = 'en_GB';

  String get _systemLocale => _regionLocaleStr;

  String get _systemDateFormat => _fmtFromLocale(_regionLocaleStr);

  static String _fmtFromLocale(String localeStr) {
    String? regionCountry;
    final rgMatch = RegExp(r'[@;]rg=([a-z]{2})zzzz', caseSensitive: false)
        .firstMatch(localeStr);
    if (rgMatch != null) regionCountry = rgMatch.group(1)!.toUpperCase();

    final normalised = localeStr.replaceAll('-', '_').split('@').first;
    final parts   = normalised.split('_');
    final country = regionCountry ?? (parts.length >= 2 ? parts[1].toUpperCase() : '');
    final lang    = parts.first.toLowerCase();

    const mdyCountries = {'US', 'CA', 'PH', 'MH', 'FM', 'PR', 'AS', 'GU', 'VI', 'MP'};
    const ymdLanguages = {'ja', 'zh', 'ko', 'mn', 'hu'};

    if (country.isNotEmpty) {
      if (mdyCountries.contains(country)) return _kFmtMDY;
      if (country.length == 2)            return _kFmtDMY;
    }
    if (ymdLanguages.contains(lang)) return _kFmtYMD;

    try {
      final skeleton = DateFormat.yMd(localeStr).pattern ?? '';
      final mPos = skeleton.indexOf('M');
      final dPos = skeleton.indexOf('d');
      final yPos = skeleton.indexOf('y');
      if (yPos >= 0 && yPos < mPos && yPos < dPos) return _kFmtYMD;
      if (mPos >= 0 && dPos >= 0 && mPos < dPos)   return _kFmtMDY;
    } catch (_) {}
    return _kFmtDMY;
  }

  String get _effectiveFormat => _manualOverride ? _dateFormat : _systemDateFormat;

  String _preview(String fmt) {
    final now = DateTime.now();
    switch (fmt) {
      case _kFmtDMY:
        return DateFormat('dd/MM/yyyy').format(now);
      case _kFmtMDY:
        return DateFormat('MM/dd/yyyy').format(now);
      case _kFmtYMD:
        return DateFormat('yyyy-MM-dd').format(now);
      default:
        return DateFormat('dd/MM/yyyy').format(now);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    // Resolve region locale: macOS → platform channel; others → PlatformDispatcher
    String regionLocale;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      try {
        regionLocale = await _kRegionChannel.invokeMethod<String>('getRegionLocale') ?? '';
        debugPrint('[RegionalScreen] macOS Locale.current.identifier = $regionLocale');
      } catch (e) {
        debugPrint('[RegionalScreen] platform channel error: $e');
        regionLocale = '';
      }
    } else {
      regionLocale = '';
    }
    if (regionLocale.isEmpty) {
      regionLocale = WidgetsBinding.instance.platformDispatcher.locale.toString();
    }
    if (mounted) {
      setState(() {
        _regionLocaleStr = regionLocale;
        _manualOverride  = p.getBool(_kManualFmt)  ?? false;
        _dateFormat      = p.getString(_kDateFmtKey) ?? _kFmtDMY;
        _loading         = false;
      });
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kManualFmt,   _manualOverride);
    await p.setString(_kDateFmtKey, _dateFormat);
    await DateFormatService.instance.reload();
    HapticUtils.success();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Regional Settings', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // ── Date & Time ─────────────────────────────────────────
                _SectionLabel('Date & Time Format'),
                Text(
                  'Affects how dates are shown throughout the app.',
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),

                // System locale info card
                GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.language_rounded, color: _teal, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('System locale',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            Text(
                              '$_systemLocale  ·  ${_preview(_systemDateFormat)}',
                              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      if (!_manualOverride)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0x2200D9B0),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('Active',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _teal)),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.tune_rounded, color: _slate),
                    title: const Text('Manual override',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'Choose a specific date format instead of using the system default.',
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                    ),
                    value: _manualOverride,
                    activeThumbColor: _teal,
                    onChanged: (v) {
                      setState(() => _manualOverride = v);
                      _save();
                    },
                  ),
                ),

                if (_manualOverride) ...[
                  const SizedBox(height: 12),
                  GlassCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        _FormatTile(
                          fmt: _kFmtDMY,
                          label: 'DD/MM/YYYY',
                          example: _preview(_kFmtDMY),
                          selected: _dateFormat == _kFmtDMY,
                          onTap: () { setState(() => _dateFormat = _kFmtDMY); _save(); },
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        _FormatTile(
                          fmt: _kFmtMDY,
                          label: 'MM/DD/YYYY',
                          example: _preview(_kFmtMDY),
                          selected: _dateFormat == _kFmtMDY,
                          onTap: () { setState(() => _dateFormat = _kFmtMDY); _save(); },
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        _FormatTile(
                          fmt: _kFmtYMD,
                          label: 'YYYY-MM-DD',
                          example: _preview(_kFmtYMD),
                          selected: _dateFormat == _kFmtYMD,
                          onTap: () { setState(() => _dateFormat = _kFmtYMD); _save(); },
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // ── Preview ─────────────────────────────────────────────
                _SectionLabel('Preview'),
                const SizedBox(height: 8),
                GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.calendar_today_outlined, size: 16, color: _teal),
                        const SizedBox(width: 8),
                        Text(
                          'Today: ${_preview(_effectiveFormat)}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                        'Format in use: $_effectiveFormat  (${_manualOverride ? 'manual' : 'system default'})',
                        style: const TextStyle(fontSize: 11, color: _slate),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Format option tile
// ---------------------------------------------------------------------------
class _FormatTile extends StatelessWidget {
  const _FormatTile({
    required this.fmt,
    required this.label,
    required this.example,
    required this.selected,
    required this.onTap,
  });

  final String fmt;
  final String label;
  final String example;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? _teal : theme.colorScheme.onSurfaceVariant,
        size: 20,
      ),
      title: Text(label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            color: selected ? _teal : theme.colorScheme.onSurface,
          )),
      trailing: Text(example,
          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
      onTap: onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// Section label
// ---------------------------------------------------------------------------
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
}
