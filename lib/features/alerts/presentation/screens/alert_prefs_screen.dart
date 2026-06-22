import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../data/alert_service.dart';

// ---------------------------------------------------------------------------
// AlertPrefsScreen — let the user toggle anomaly + budget alerts
// ---------------------------------------------------------------------------
class AlertPrefsScreen extends ConsumerStatefulWidget {
  const AlertPrefsScreen({super.key});

  @override
  ConsumerState<AlertPrefsScreen> createState() => _AlertPrefsScreenState();
}

class _AlertPrefsScreenState extends ConsumerState<AlertPrefsScreen> {
  AlertPrefs? _prefs;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await ref.read(alertServiceProvider).getPrefs();
    if (mounted) setState(() { _prefs = prefs; _loading = false; });
  }

  Future<void> _save(AlertPrefs updated) async {
    setState(() { _saving = true; _prefs = updated; });
    try {
      await ref.read(alertServiceProvider).savePrefs(updated);
      ref.invalidate(alertPrefsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'alerts.prefs_title'.tr(),
          style: const TextStyle(
              fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: -0.3),
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final p = _prefs!;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        // ── Anomaly alerts ───────────────────────────────────────────────
        _SectionHeader(label: 'alerts.anomaly_section'.tr()),
        const SizedBox(height: 8),
        _ToggleTile(
          icon: Icons.trending_up_rounded,
          iconColor: const Color(0xFFF59E0B),
          title: 'alerts.anomaly_toggle_title'.tr(),
          subtitle: 'alerts.anomaly_toggle_subtitle'.tr(),
          value: p.anomalyEnabled,
          onChanged: _saving
              ? null
              : (v) => _save(p.copyWith(anomalyEnabled: v)),
        ),
        if (p.anomalyEnabled) ...[
          const SizedBox(height: 10),
          _StepperTile(
            label: 'alerts.anomaly_k_label'.tr(),
            subtitle: 'alerts.anomaly_k_subtitle'.tr(),
            value: p.anomalyK,
            min: 1.5,
            max: 5.0,
            step: 0.5,
            display: (v) => '${v.toStringAsFixed(1)}×',
            onChanged: _saving ? null : (v) => _save(p.copyWith(anomalyK: v)),
          ),
          const SizedBox(height: 10),
          _StepperTile(
            label: 'alerts.anomaly_months_label'.tr(),
            subtitle: 'alerts.anomaly_months_subtitle'.tr(),
            value: p.anomalyMonths.toDouble(),
            min: 1,
            max: 6,
            step: 1,
            display: (v) => '${v.toInt()} mo',
            onChanged: _saving
                ? null
                : (v) => _save(p.copyWith(anomalyMonths: v.toInt())),
          ),
        ],
        const SizedBox(height: 24),

        // ── Budget alerts ───────────────────────────────────────────────
        _SectionHeader(label: 'alerts.budget_section'.tr()),
        const SizedBox(height: 8),
        _ToggleTile(
          icon: Icons.warning_amber_rounded,
          iconColor: const Color(0xFFF97316),
          title: 'alerts.budget80_toggle_title'.tr(),
          subtitle: 'alerts.budget80_toggle_subtitle'.tr(),
          value: p.budget80Enabled,
          onChanged: _saving
              ? null
              : (v) => _save(p.copyWith(budget80Enabled: v)),
        ),
        const SizedBox(height: 8),
        _ToggleTile(
          icon: Icons.warning_rounded,
          iconColor: const Color(0xFFEF4444),
          title: 'alerts.budget100_toggle_title'.tr(),
          subtitle: 'alerts.budget100_toggle_subtitle'.tr(),
          value: p.budget100Enabled,
          onChanged: _saving
              ? null
              : (v) => _save(p.copyWith(budget100Enabled: v)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(100)),
      ),
      child: SwitchListTile.adaptive(
        secondary: Icon(icon, color: iconColor, size: 20),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(subtitle,
            style: TextStyle(
                fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
        value: value,
        onChanged: onChanged,
        activeTrackColor: iconColor,
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _StepperTile extends StatelessWidget {
  const _StepperTile({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.display,
    required this.onChanged,
  });
  final String label;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final double step;
  final String Function(double) display;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(100)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StepBtn(
                  icon: Icons.remove,
                  enabled: onChanged != null && value > min,
                  onTap: () => onChanged?.call(
                      (value - step).clamp(min, max)),
                ),
                const SizedBox(width: 8),
                Text(display(value),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(width: 8),
                _StepBtn(
                  icon: Icons.add,
                  enabled: onChanged != null && value < max,
                  onTap: () => onChanged?.call(
                      (value + step).clamp(min, max)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn(
      {required this.icon, required this.enabled, required this.onTap});
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: enabled
              ? theme.colorScheme.secondaryContainer
              : theme.colorScheme.onSurface.withAlpha(20),
        ),
        child: Icon(
          icon,
          size: 14,
          color: enabled
              ? theme.colorScheme.onSecondaryContainer
              : theme.colorScheme.onSurface.withAlpha(60),
        ),
      ),
    );
  }
}
