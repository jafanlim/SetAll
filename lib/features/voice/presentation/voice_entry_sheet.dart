import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/voice_entry_result.dart';
import '../../../core/providers/setall_providers.dart';
import '../../../core/services/voice_entry_service.dart';
import '../../../core/utils/haptic_utils.dart';
import '../../../data/models/group_model.dart';
import '../../../data/repositories/setall_repository.dart' show SplitInsert;
import '../../../domain/entities/expense.dart' show SplitType;

// ── Brand colours ──────────────────────────────────────────────────────────
const _teal        = Color(0xFF00D9B0);
const _purple      = Color(0xFF7C3AED);
const _orange      = Color(0xFFFF8C42);
const _surfaceDark = Color(0xFF0F172A);

enum VoiceEntryState {
  listening,
  processing,
  clarifying,
  confirming,
  saving,
  done,
  error,
}

class VoiceEntrySheet extends ConsumerStatefulWidget {
  const VoiceEntrySheet({
    super.key,
    required this.groups,
    required this.defaultCurrency,
  });

  final List<GroupModel> groups;
  final String defaultCurrency;

  @override
  ConsumerState<VoiceEntrySheet> createState() => _VoiceEntrySheetState();
}

class _VoiceEntrySheetState extends ConsumerState<VoiceEntrySheet>
    with TickerProviderStateMixin {
  VoiceEntryState _state = VoiceEntryState.listening;
  String _partial   = '';
  String _transcript = '';
  String _errorMsg  = '';
  int    _retryCount = 0;
  VoiceEntryResult? _result;

  // Inline edit state (initialised when entering confirming)
  double _editAmount      = 0;
  String _editCurrency    = 'USD';
  String _editDescription = '';

  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulseAnim;

  final TextEditingController _clarifyCtrl   = TextEditingController();
  final TextEditingController _amountCtrl    = TextEditingController();
  final TextEditingController _descCtrl      = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _startListening());
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _clarifyCtrl.dispose();
    _amountCtrl.dispose();
    _descCtrl.dispose();
    VoiceEntryService.instance.cancel();
    super.dispose();
  }

  // ── Core flow ──────────────────────────────────────────────────────────

  Future<void> _startListening() async {
    if (!mounted) return;
    setState(() {
      _state   = VoiceEntryState.listening;
      _partial = '';
    });
    _pulseCtrl.repeat(reverse: true);

    try {
      final locale = EasyLocalization.of(context)?.locale.toString();
      final transcript = await VoiceEntryService.instance.listen(
        onPartial: (p) {
          if (mounted) setState(() => _partial = p);
        },
        preferredLocale: locale,
      );
      if (transcript.trim().isEmpty) {
        // STT returned empty — likely error_no_match or error_speech_timeout.
        // Transient: show a brief hint and retry automatically (up to 3 times).
        if (_retryCount < 3) {
          _retryCount++;
          if (mounted) {
            setState(() => _partial = 'voice_entry.couldnt_hear'.tr());
          }
          await Future.delayed(const Duration(milliseconds: 1500));
          await _startListening();
        } else {
          _retryCount = 0;
          if (mounted) {
            setState(() {
              _state    = VoiceEntryState.error;
              _errorMsg = 'voice_entry.couldnt_hear'.tr();
            });
          }
        }
        return;
      }
      _retryCount = 0;
      _transcript = transcript;
      await _parse(_transcript);
    } catch (e) {
      if (mounted) {
        setState(() {
          _state    = VoiceEntryState.error;
          _errorMsg = 'voice_entry.error_title'.tr();
        });
      }
    }
  }

  Future<void> _stopEarly() async {
    HapticUtils.lightTap();
    await VoiceEntryService.instance.stop();
    _transcript = _partial;
    if (_transcript.trim().isEmpty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    await _parse(_transcript);
  }

  Future<void> _parse(String transcript) async {
    if (!mounted) return;
    setState(() => _state = VoiceEntryState.processing);
    _pulseCtrl.stop();

    try {
      final groupMaps = widget.groups
          .map((g) => {'id': g.id, 'name': g.name})
          .toList();

      final result = await VoiceEntryService.instance.parse(
        transcript,
        groupMaps,
        widget.defaultCurrency,
      );

      if (!mounted) return;
      if (result.needsClarification != null) {
        setState(() {
          _result = result;
          _state  = VoiceEntryState.clarifying;
        });
      } else {
        _editAmount      = result.amount;
        _editCurrency    = result.currency;
        _editDescription = result.description;
        _amountCtrl.text = result.amount.toStringAsFixed(2);
        _descCtrl.text   = result.description;
        setState(() {
          _result = result;
          _state  = VoiceEntryState.confirming;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state    = VoiceEntryState.error;
          _errorMsg = 'Could not parse entry. Please try again.';
        });
      }
    }
  }

  Future<void> _submitClarification() async {
    final clarification = _clarifyCtrl.text.trim();
    if (clarification.isEmpty) return;
    _clarifyCtrl.clear();
    _transcript = '$_transcript $clarification';
    await _parse(_transcript);
  }

  Future<void> _confirm() async {
    final result = _result;
    if (result == null) return;
    HapticUtils.primaryTap();

    // Fuzzy match group if needed
    String? resolvedGroupId;
    if (result.type == 'group') {
      final hint  = (result.groupNameHint ?? '').toLowerCase();
      final match = widget.groups.firstWhere(
        (g) => g.name.toLowerCase().contains(hint) || hint.contains(g.name.toLowerCase()),
        orElse: () => GroupModel(id: '', name: '', creatorId: ''),
      );
      if (match.id.isEmpty) {
        setState(() {
          _result = VoiceEntryResult(
            type:               result.type,
            amount:             result.amount,
            currency:           result.currency,
            description:        result.description,
            category:           result.category,
            isIncome:           result.isIncome,
            groupNameHint:      result.groupNameHint,
            splitMode:          result.splitMode,
            needsClarification: 'group_not_found',
          );
          _state = VoiceEntryState.clarifying;
        });
        return;
      }
      resolvedGroupId = match.id;
    }

    setState(() => _state = VoiceEntryState.saving);

    try {
      final repo   = ref.read(setAllRepositoryProvider);
      final uid    = await repo.ensureUser();
      if (uid == null) throw Exception('Not authenticated');

      // Use inline-edited values, not raw result fields
      final amountDecimal = Decimal.parse(_editAmount.toStringAsFixed(2));
      final currency      = _editCurrency;
      final description   = _editDescription.trim().isEmpty ? result.description : _editDescription.trim();

      // Build even-split list for group entries
      List<SplitInsert> splits = [];
      if (result.type == 'group' && resolvedGroupId != null && result.splitMode == 'even') {
        final members = await repo.getGroupMembers(resolvedGroupId);
        if (members.isEmpty) {
          splits = [SplitInsert(
            userId: uid,
            universalUsdOwed: amountDecimal,
          )];
        } else {
          final count = Decimal.fromInt(members.length);
          final share = (amountDecimal / count).toDecimal(scaleOnInfinitePrecision: 2);
          splits = members.map((m) => SplitInsert(
            userId: m.id,
            universalUsdOwed: share,
          )).toList();
        }
      } else {
        splits = [SplitInsert(
          userId: uid,
          universalUsdOwed: amountDecimal,
        )];
      }

      await repo.addExpense(
        groupId:     resolvedGroupId,
        payerId:     uid,
        amount:      amountDecimal,
        description: description,
        currency:    currency,
        splitType:   result.splitMode == 'even' ? SplitType.even : SplitType.manual,
        splits:      splits,
        category:    result.category,
        isIncome:    result.isIncome,
      );

      ref.invalidate(balanceSummaryProvider);
      ref.invalidate(recentExpensesProvider);
      ref.invalidate(myGroupsProvider);

      if (!mounted) return;
      setState(() => _state = VoiceEntryState.done);

      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) Navigator.of(context).pop();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _state    = VoiceEntryState.error;
          _errorMsg = 'Failed to save. Please try again.';
        });
      }
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: _surfaceDark,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            _buildHandle(),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case VoiceEntryState.listening:   return _buildListening();
      case VoiceEntryState.processing:  return _buildProcessing();
      case VoiceEntryState.clarifying:  return _buildClarifying();
      case VoiceEntryState.confirming:  return _buildConfirming();
      case VoiceEntryState.saving:      return _buildSaving();
      case VoiceEntryState.done:        return _buildDone();
      case VoiceEntryState.error:       return _buildError();
    }
  }

  // ── LISTENING ────────────────────────────────────────────────────────────

  Widget _buildListening() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 24),
        ScaleTransition(
          scale: _pulseAnim,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _purple.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: _purple.withValues(alpha: 0.5), width: 2),
            ),
            child: const Icon(Icons.mic_rounded, color: _purple, size: 36),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'voice_entry.listening'.tr(),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _partial.isEmpty ? 'Speak your expense or income' : _partial,
          style: TextStyle(
            fontSize: 14,
            color: _partial.isEmpty ? Colors.white38 : Colors.white70,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: 64,
          height: 64,
          child: FloatingActionButton(
            heroTag: 'voiceStopFab',
            onPressed: _stopEarly,
            backgroundColor: Colors.white12,
            elevation: 0,
            child: const Icon(Icons.stop_rounded, color: Colors.white, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text('voice_entry.tap_to_stop'.tr(), style: const TextStyle(fontSize: 11, color: Colors.white38)),
      ],
    );
  }

  // ── PROCESSING ───────────────────────────────────────────────────────────

  Widget _buildProcessing() {
    return Column(
      children: [
        const SizedBox(height: 60),
        const CircularProgressIndicator(color: _teal),
        const SizedBox(height: 24),
        Text(
          'voice_entry.processing'.tr(),
          style: const TextStyle(fontSize: 16, color: Colors.white70),
        ),
        const SizedBox(height: 60),
      ],
    );
  }

  // ── CLARIFYING ───────────────────────────────────────────────────────────

  Widget _buildClarifying() {
    final key      = _result?.needsClarification;
    final question = _clarificationQuestion(key);
    final showGroupChips = (key == 'group_not_found' || key == 'group_name') &&
        widget.groups.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Icon(Icons.help_outline_rounded, color: _orange, size: 36),
        const SizedBox(height: 16),
        Text(
          question,
          style: const TextStyle(fontSize: 16, color: Colors.white, height: 1.4),
        ),
        const SizedBox(height: 16),

        // Tappable group chips for group_not_found / group_name
        if (showGroupChips) ...
          [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.groups.map((g) => ActionChip(
                label: Text(g.name),
                labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                backgroundColor: _teal.withValues(alpha: 0.15),
                side: BorderSide(color: _teal.withValues(alpha: 0.4)),
                onPressed: () {
                  _clarifyCtrl.text = g.name;
                  _submitClarification();
                },
              )).toList(),
            ),
            const SizedBox(height: 16),
          ],

        TextField(
          controller: _clarifyCtrl,
          autofocus: !showGroupChips,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Or type your answer...',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white10,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _teal),
            ),
          ),
          onSubmitted: (_) => _submitClarification(),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _submitClarification,
            style: FilledButton.styleFrom(
              backgroundColor: _teal,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('voice_entry.confirm_btn'.tr(), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  String _clarificationQuestion(String? key) {
    final groupNames = widget.groups.map((g) => g.name).join(', ');
    switch (key) {
      case 'currency':         return 'Which currency? e.g. USD, GEL, EUR';
      case 'amount':           return 'How much?';
      case 'group_name':       return 'Which group? $groupNames';
      case 'income_or_expense':return 'Income or expense?';
      case 'group_not_found':  return 'Group not found. Which group? $groupNames';
      default:                 return 'Could you clarify?';
    }
  }

  // ── CONFIRMING ───────────────────────────────────────────────────────────

  static const _commonCurrencies = ['USD', 'AED', 'GEL', 'EUR', 'GBP', 'RUB', 'CNY', 'VND', 'INR'];

  Widget _buildConfirming() {
    final r = _result!;
    final isIncome    = r.isIncome;
    final amountColor = isIncome ? _teal : _orange;
    final sign        = isIncome ? '+' : '-';

    String groupLabel = 'WALLET';
    if (r.type == 'group' && r.groupNameHint != null) {
      final hint  = r.groupNameHint!.toLowerCase();
      final match = widget.groups.firstWhere(
        (g) => g.name.toLowerCase().contains(hint) || hint.contains(g.name.toLowerCase()),
        orElse: () => GroupModel(id: '', name: r.groupNameHint!, creatorId: ''),
      );
      groupLabel = match.name.toUpperCase();
    }

    // Ensure dropdown value is in the list
    final currencyValue = _commonCurrencies.contains(_editCurrency)
        ? _editCurrency
        : _commonCurrencies.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Type badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: r.type == 'group'
                      ? _teal.withValues(alpha: 0.15)
                      : Colors.white10,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  groupLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: r.type == 'group' ? _teal : Colors.white54,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Amount preview
              Text(
                '$sign$_editCurrency ${_editAmount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: amountColor,
                ),
              ),
              const SizedBox(height: 14),

              // Editable: Amount + Currency row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _darkField(
                      controller: _amountCtrl,
                      label: 'voice_entry.amount_label'.tr(),
                      keyboard: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed != null) setState(() => _editAmount = parsed);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: currencyValue,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          items: _commonCurrencies
                              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _editCurrency = v);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Editable: Description
              _darkField(
                controller: _descCtrl,
                label: 'voice_entry.description_label'.tr(),
                onChanged: (v) => setState(() => _editDescription = v),
              ),
              const SizedBox(height: 12),

              // Category chip (display-only)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Chip(label: r.category, color: _purple),
                  if (r.isIncome) _Chip(label: 'Income', color: _teal),
                  if (r.splitMode == 'none') _Chip(label: 'No split', color: Colors.white38),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Confirm button
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _confirm,
            icon: const Icon(Icons.check_rounded),
            label: Text('voice_entry.confirm_btn'.tr(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            style: FilledButton.styleFrom(
              backgroundColor: _teal,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Cancel button
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () {
              HapticUtils.lightTap();
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.white38),
            child: Text('voice_entry.cancel_btn'.tr()),
          ),
        ),
      ],
    );
  }

  Widget _darkField({
    required TextEditingController controller,
    required String label,
    TextInputType keyboard = TextInputType.text,
    void Function(String)? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      style: const TextStyle(color: Colors.white),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
        filled: true,
        fillColor: Colors.white10,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _teal),
        ),
      ),
    );
  }

  // ── SAVING ───────────────────────────────────────────────────────────────

  Widget _buildSaving() {
    return Column(
      children: [
        SizedBox(height: 60),
        SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(color: _teal, strokeWidth: 2.5),
        ),
        SizedBox(height: 20),
        Text(
          'voice_entry.saving'.tr(),
          style: const TextStyle(fontSize: 16, color: Colors.white70),
        ),
        SizedBox(height: 60),
      ],
    );
  }

  // ── DONE ─────────────────────────────────────────────────────────────────

  Widget _buildDone() {
    return Column(
      children: [
        SizedBox(height: 48),
        Icon(Icons.check_circle_rounded, color: _teal, size: 64),
        SizedBox(height: 16),
        Text(
          'voice_entry.saved'.tr(),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        SizedBox(height: 48),
      ],
    );
  }

  // ── ERROR ─────────────────────────────────────────────────────────────────

  Widget _buildError() {
    return Column(
      children: [
        const SizedBox(height: 40),
        const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 52),
        const SizedBox(height: 16),
        Text(
          _errorMsg,
          style: const TextStyle(fontSize: 15, color: Colors.white70),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _startListening,
            style: FilledButton.styleFrom(
              backgroundColor: _purple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('voice_entry.error_retry'.tr(), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

// ── Small category/label chip ─────────────────────────────────────────────

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
