import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
const _kTimeFmtKey   = 'regional_time_format';
const _kManualTime   = 'regional_manual_time_override';

const _kFmtDMY  = 'DD/MM/YYYY';
const _kFmtMDY  = 'MM/DD/YYYY';
const _kFmtYMD  = 'YYYY-MM-DD';
const _kFmt24h  = '24h';
const _kFmt12h  = '12h';

// ---------------------------------------------------------------------------
// RegionalScreen
// ---------------------------------------------------------------------------
class RegionalScreen extends StatefulWidget {
  const RegionalScreen({super.key});

  @override
  State<RegionalScreen> createState() => _RegionalScreenState();
}

class _RegionalScreenState extends State<RegionalScreen> {
  bool   _manualOverride     = false;
  String _dateFormat         = _kFmtDMY;
  bool   _manualTimeOverride = false;
  String _timeFormat         = _kFmt24h;
  bool   _loading            = true;
  // Resolved region locale string — on macOS comes from platform channel
  String _regionLocaleStr    = 'en_GB';

  String get _systemLocale => _regionLocaleStr;

  String get _systemDateFormat => _fmtFromLocale(_regionLocaleStr);

  String get _systemTimeFormat {
    // Check @hours= ICU extension (macOS)
    final hoursMatch = RegExp(r'[@;]hours=(h\d+)', caseSensitive: false)
        .firstMatch(_regionLocaleStr);
    if (hoursMatch != null) {
      final h = hoursMatch.group(1)!.toLowerCase();
      return (h == 'h23' || h == 'h24') ? _kFmt24h : _kFmt12h;
    }
    // Fallback: intl jm() skeleton
    try {
      final skeleton = DateFormat.jm(_regionLocaleStr.split('@').first).pattern ?? '';
      if (skeleton.contains('a') || skeleton.toLowerCase().contains('h:')) return _kFmt12h;
    } catch (_) {}
    return _kFmt24h;
  }

  String get _effectiveTimeFormat => _manualTimeOverride ? _timeFormat : _systemTimeFormat;

  String _previewTime(String fmt) {
    final now = DateTime.now();
    return DateFormat(fmt == _kFmt12h ? 'h:mm a' : 'HH:mm').format(now);
  }

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
        _regionLocaleStr   = regionLocale;
        _manualOverride    = p.getBool(_kManualFmt)    ?? false;
        _dateFormat        = p.getString(_kDateFmtKey) ?? _kFmtDMY;
        _manualTimeOverride = p.getBool(_kManualTime)  ?? false;
        _timeFormat        = p.getString(_kTimeFmtKey) ?? _kFmt24h;
        _loading           = false;
      });
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kManualFmt,    _manualOverride);
    await p.setString(_kDateFmtKey, _dateFormat);
    await p.setBool(_kManualTime,   _manualTimeOverride);
    await p.setString(_kTimeFmtKey, _timeFormat);
    await DateFormatService.instance.reload();
    HapticUtils.success();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text('settings_ext.regional'.tr(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
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
                _SectionLabel('regional.date_time_format'.tr()),
                Text(
                  'regional.date_time_subtitle'.tr(),
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
                            Text('regional.system_locale'.tr(),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
                          child: Text('regional.active'.tr(),
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _teal)),
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
                    title: Text('regional.manual_override'.tr(),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'regional.manual_override_subtitle'.tr(),
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

                const SizedBox(height: 28),

                // ── Time Format ──────────────────────────────────────────
                _SectionLabel('regional.time_format'.tr()),
                Text(
                  'regional.time_format_subtitle'.tr(),
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),

                GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time_rounded, color: _teal, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('regional.system_time_format'.tr(),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            Text(
                              '$_systemTimeFormat  ·  ${_previewTime(_systemTimeFormat)}',
                              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      if (!_manualTimeOverride)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0x2200D9B0),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('regional.active'.tr(),
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _teal)),
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
                    title: Text('regional.manual_override'.tr(),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'regional.manual_time_subtitle'.tr(),
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                    ),
                    value: _manualTimeOverride,
                    activeThumbColor: _teal,
                    onChanged: (v) {
                      setState(() => _manualTimeOverride = v);
                      _save();
                    },
                  ),
                ),

                if (_manualTimeOverride) ...[
                  const SizedBox(height: 12),
                  GlassCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        _FormatTile(
                          fmt: _kFmt24h,
                          label: '24-hour  (14:30)',
                          example: _previewTime(_kFmt24h),
                          selected: _timeFormat == _kFmt24h,
                          onTap: () { setState(() => _timeFormat = _kFmt24h); _save(); },
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        _FormatTile(
                          fmt: _kFmt12h,
                          label: '12-hour  (2:30 PM)',
                          example: _previewTime(_kFmt12h),
                          selected: _timeFormat == _kFmt12h,
                          onTap: () { setState(() => _timeFormat = _kFmt12h); _save(); },
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // ── Preview ─────────────────────────────────────────────
                _SectionLabel('regional.preview'.tr()),
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
                          'Today: ${_preview(_effectiveFormat)}  ${_previewTime(_effectiveTimeFormat)}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                        'Date: $_effectiveFormat  (${_manualOverride ? 'manual' : 'system default'})',
                        style: const TextStyle(fontSize: 11, color: _slate),
                      ),
                      Text(
                        'Time: $_effectiveTimeFormat  (${_manualTimeOverride ? 'manual' : 'system default'})',
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
