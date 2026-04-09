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
import '../../../data/models/profile_model.dart';
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
  multiConfirming,
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
  String _partial    = '';
  String _transcript = '';
  String _errorMsg   = '';
  int    _retryCount = 0;

  // Single confirming state (add_expense only)
  AddExpenseAction? _singleResult;

  // Inline edit state for single confirming
  double _editAmount      = 0;
  String _editCurrency    = 'USD';
  String _editDescription = '';

  // Multi-action stepper state
  List<VoiceAction> _pendingActions    = [];
  int               _currentActionIdx  = 0;
  // Resolved group from a create_group step (used by subsequent add_member/add_expense)
  GroupModel?       _createdGroup;
  // User search results for current add_member step
  List<ProfileModel> _memberSearchResults = [];
  bool               _memberSearching     = false;

  // Clarifying state — points to the action being clarified
  AddExpenseAction? _clarifyingResult;

  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulseAnim;

  final TextEditingController _clarifyCtrl      = TextEditingController();
  final TextEditingController _amountCtrl       = TextEditingController();
  final TextEditingController _descCtrl         = TextEditingController();
  final TextEditingController _memberSearchCtrl = TextEditingController();

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
    _memberSearchCtrl.dispose();
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
        if (_retryCount < 3) {
          _retryCount++;
          if (mounted) setState(() => _partial = 'voice_entry.couldnt_hear'.tr());
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

      final langCode = EasyLocalization.of(context)?.locale.languageCode ?? 'en';
      final translatedCategories = [
        'categories.food_drink'.tr(),
        'categories.transport'.tr(),
        'categories.travel'.tr(),
        'categories.entertainment'.tr(),
        'categories.bills_utilities'.tr(),
        'categories.shopping'.tr(),
        'categories.general'.tr(),
        'categories.other'.tr(),
      ];
      final response = await VoiceEntryService.instance.parse(
        transcript,
        groupMaps,
        widget.defaultCurrency,
        language: langCode,
        knownCategories: translatedCategories,
      );

      if (!mounted) return;

      // Top-level clarification (e.g. empty/no amount)
      if (response.actions.isEmpty && response.needsClarification != null) {
        _clarifyingResult = null;
        setState(() => _state = VoiceEntryState.clarifying);
        return;
      }

      // Single add_expense → existing confirming flow
      if (response.actions.length == 1 && response.actions.first is AddExpenseAction) {
        final action = response.actions.first as AddExpenseAction;
        if (action.needsClarification != null) {
          _clarifyingResult = action;
          setState(() => _state = VoiceEntryState.clarifying);
          return;
        }
        _singleResult    = action;
        _editAmount      = action.amount;
        _editCurrency    = action.currency;
        _editDescription = action.description;
        _amountCtrl.text = action.amount.toStringAsFixed(2);
        _descCtrl.text   = action.description;
        setState(() => _state = VoiceEntryState.confirming);
        return;
      }

      // Multi-action stepper
      _pendingActions   = response.actions;
      _currentActionIdx = 0;
      _createdGroup     = null;
      setState(() => _state = VoiceEntryState.multiConfirming);
      _prepareCurrentMultiStep();
    } catch (e) {
      if (mounted) {
        setState(() {
          _state    = VoiceEntryState.error;
          _errorMsg = 'voice_entry.error_title'.tr();
        });
      }
    }
  }

  // ── Clarification ─────────────────────────────────────────────────────

  Future<void> _submitClarification() async {
    final clarification = _clarifyCtrl.text.trim();
    if (clarification.isEmpty) return;
    _clarifyCtrl.clear();
    _transcript = '$_transcript $clarification';
    await _parse(_transcript);
  }

  // ── Single confirming ─────────────────────────────────────────────────

  Future<void> _confirmSingle() async {
    final action = _singleResult;
    if (action == null) return;
    HapticUtils.primaryTap();

    String? resolvedGroupId;
    if (action.groupNameHint != null) {
      final hint  = action.groupNameHint!.toLowerCase();
      final match = widget.groups.firstWhere(
        (g) => g.name.toLowerCase().contains(hint) || hint.contains(g.name.toLowerCase()),
        orElse: () => GroupModel(id: '', name: '', creatorId: ''),
      );
      if (match.id.isEmpty) {
        _clarifyingResult = action.copyWith(needsClarification: 'group_not_found');
        setState(() => _state = VoiceEntryState.clarifying);
        return;
      }
      resolvedGroupId = match.id;
    }

    setState(() => _state = VoiceEntryState.saving);
    try {
      await _executeAddExpense(action, resolvedGroupId, useEditFields: true);
      if (!mounted) return;
      setState(() => _state = VoiceEntryState.done);
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) Navigator.of(context).pop();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _state    = VoiceEntryState.error;
          _errorMsg = 'voice_entry.error_title'.tr();
        });
      }
    }
  }

  // ── Multi-action stepper ──────────────────────────────────────────────

  void _prepareCurrentMultiStep() {
    final action = _pendingActions[_currentActionIdx];
    if (action is AddMemberAction) {
      _searchMemberForStep(action.memberNameHint);
    }
  }

  Future<void> _searchMemberForStep(String hint) async {
    if (!mounted) return;
    setState(() {
      _memberSearchResults = [];
      _memberSearching     = true;
    });
    try {
      final repo    = ref.read(setAllRepositoryProvider);
      final results = await repo.searchUsers(hint);
      if (mounted) setState(() { _memberSearchResults = results; _memberSearching = false; });
    } catch (_) {
      if (mounted) setState(() => _memberSearching = false);
    }
  }

  Future<void> _confirmMultiStep() async {
    HapticUtils.primaryTap();
    final action = _pendingActions[_currentActionIdx];

    setState(() => _state = VoiceEntryState.saving);
    try {
      await _executeAction(action);
    } catch (e) {
      if (mounted) {
        setState(() {
          _state    = VoiceEntryState.error;
          _errorMsg = e.toString();
        });
      }
      return;
    }

    _advanceMultiStep();
  }

  void _skipMultiStep() {
    HapticUtils.lightTap();
    _advanceMultiStep();
  }

  void _advanceMultiStep() {
    final nextIdx = _currentActionIdx + 1;
    if (nextIdx >= _pendingActions.length) {
      // All done
      if (!mounted) return;
      ref.invalidate(balanceSummaryProvider);
      ref.invalidate(recentExpensesProvider);
      ref.invalidate(myGroupsProvider);
      setState(() => _state = VoiceEntryState.done);
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) Navigator.of(context).pop();
      });
    } else {
      if (!mounted) return;
      setState(() {
        _currentActionIdx = nextIdx;
        _state = VoiceEntryState.multiConfirming;
      });
      _prepareCurrentMultiStep();
    }
  }

  Future<void> _executeAction(VoiceAction action) async {
    if (action is CreateGroupAction) {
      final repo  = ref.read(setAllRepositoryProvider);
      final group = await repo.createGroup(action.name);
      if (group != null) _createdGroup = group;

    } else if (action is AddMemberAction) {
      final repo    = ref.read(setAllRepositoryProvider);
      final groupId = _resolveGroupId(action.groupNameHint);
      if (groupId == null) return; // skip silently if no group to add to
      if (_memberSearchResults.isNotEmpty) {
        await repo.addMemberById(groupId, _memberSearchResults.first.id);
      }

    } else if (action is AddExpenseAction) {
      final groupId = _resolveGroupId(action.groupNameHint);
      await _executeAddExpense(action, groupId);
      ref.invalidate(balanceSummaryProvider);
      ref.invalidate(recentExpensesProvider);
      ref.invalidate(myGroupsProvider);
    }
  }

  String? _resolveGroupId(String? hint) {
    if (_createdGroup != null) return _createdGroup!.id;
    if (hint == null) return null;
    final h = hint.toLowerCase();
    final match = widget.groups.firstWhere(
      (g) => g.name.toLowerCase().contains(h) || h.contains(g.name.toLowerCase()),
      orElse: () => GroupModel(id: '', name: '', creatorId: ''),
    );
    return match.id.isEmpty ? null : match.id;
  }

  Future<void> _executeAddExpense(
    AddExpenseAction action,
    String? groupId, {
    bool useEditFields = false,
  }) async {
    final repo   = ref.read(setAllRepositoryProvider);
    final uid    = await repo.ensureUser();
    if (uid == null) throw Exception('Not authenticated');

    final resolvedAmount = useEditFields ? _editAmount : action.amount;
    final resolvedCurrency = useEditFields ? _editCurrency : action.currency;
    final resolvedDesc = (useEditFields && _editDescription.trim().isNotEmpty)
        ? _editDescription.trim()
        : action.description;

    final amountDecimal = Decimal.parse(resolvedAmount.toStringAsFixed(2));
    final currency      = resolvedCurrency;
    final description   = resolvedDesc;

    List<SplitInsert> splits = [];
    if (groupId != null && action.splitMode == 'even') {
      final members = await repo.getGroupMembers(groupId);
      if (members.isEmpty) {
        splits = [SplitInsert(userId: uid, universalUsdOwed: amountDecimal)];
      } else {
        final count = Decimal.fromInt(members.length);
        final share = (amountDecimal / count).toDecimal(scaleOnInfinitePrecision: 2);
        splits = members.map((m) => SplitInsert(userId: m.id, universalUsdOwed: share)).toList();
      }
    } else {
      splits = [SplitInsert(userId: uid, universalUsdOwed: amountDecimal)];
    }

    await repo.addExpense(
      groupId:     groupId,
      payerId:     uid,
      amount:      amountDecimal,
      description: description,
      currency:    currency,
      splitType:   action.splitMode == 'even' ? SplitType.even : SplitType.manual,
      splits:      splits,
      category:    action.category,
      isIncome:    action.isIncome,
    );
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
      case VoiceEntryState.listening:        return _buildListening();
      case VoiceEntryState.processing:       return _buildProcessing();
      case VoiceEntryState.clarifying:       return _buildClarifying();
      case VoiceEntryState.confirming:       return _buildConfirming();
      case VoiceEntryState.multiConfirming:  return _buildMultiConfirming();
      case VoiceEntryState.saving:           return _buildSaving();
      case VoiceEntryState.done:             return _buildDone();
      case VoiceEntryState.error:            return _buildError();
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
          _partial.isEmpty ? 'voice_entry.listening_hint'.tr() : _partial,
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
    final key      = _clarifyingResult?.needsClarification;
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

        if (showGroupChips) ...[
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
      case 'currency':          return 'Which currency? e.g. USD, GEL, EUR';
      case 'amount':            return 'How much?';
      case 'group_name':        return 'Which group? $groupNames';
      case 'income_or_expense': return 'Income or expense?';
      case 'group_not_found':   return 'Group not found. Which group? $groupNames';
      default:                  return 'Could you clarify?';
    }
  }

  // ── CONFIRMING (single add_expense) ──────────────────────────────────────

  static const _commonCurrencies = ['USD', 'AED', 'GEL', 'EUR', 'GBP', 'RUB', 'CNY', 'VND', 'INR'];

  Widget _buildConfirming() {
    final r = _singleResult!;
    final isIncome    = r.isIncome;
    final amountColor = isIncome ? _teal : _orange;
    final sign        = isIncome ? '+' : '-';

    String groupLabel = 'WALLET';
    if (r.groupNameHint != null) {
      final hint  = r.groupNameHint!.toLowerCase();
      final match = widget.groups.firstWhere(
        (g) => g.name.toLowerCase().contains(hint) || hint.contains(g.name.toLowerCase()),
        orElse: () => GroupModel(id: '', name: r.groupNameHint!, creatorId: ''),
      );
      groupLabel = match.name.toUpperCase();
    }

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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: r.groupNameHint != null
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
                    color: r.groupNameHint != null ? _teal : Colors.white54,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '$sign$_editCurrency ${_editAmount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: amountColor,
                ),
              ),
              const SizedBox(height: 14),
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
              _darkField(
                controller: _descCtrl,
                label: 'voice_entry.description_label'.tr(),
                onChanged: (v) => setState(() => _editDescription = v),
              ),
              const SizedBox(height: 12),
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
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _confirmSingle,
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

  // ── MULTI-CONFIRMING stepper ──────────────────────────────────────────────

  Widget _buildMultiConfirming() {
    if (_pendingActions.isEmpty) return _buildSaving();
    final total  = _pendingActions.length;
    final n      = _currentActionIdx + 1;
    final action = _pendingActions[_currentActionIdx];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        // Step counter
        Text(
          'voice_entry.step_x_of_y'.tr(namedArgs: {'n': '$n', 'total': '$total'}),
          style: const TextStyle(fontSize: 12, color: Colors.white38, fontWeight: FontWeight.w600, letterSpacing: 0.6),
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: n / total,
          backgroundColor: Colors.white12,
          color: _teal,
          minHeight: 3,
          borderRadius: BorderRadius.circular(2),
        ),
        const SizedBox(height: 20),

        // Action-specific card
        _buildActionCard(action),

        const SizedBox(height: 20),

        // Confirm button
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: (action is AddMemberAction && _memberSearching)
                ? null
                : _confirmMultiStep,
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

        // Skip button
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: _skipMultiStep,
            style: TextButton.styleFrom(foregroundColor: Colors.white38),
            child: Text('voice_entry.action_skip'.tr()),
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard(VoiceAction action) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: switch (action) {
        CreateGroupAction a => _buildCreateGroupCard(a),
        AddMemberAction   a => _buildAddMemberCard(a),
        AddExpenseAction  a => _buildExpenseCard(a),
      },
    );
  }

  Widget _buildCreateGroupCard(CreateGroupAction action) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: _purple.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: const Icon(Icons.group_add_rounded, color: _purple, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'voice_entry.create_group_confirm'.tr(namedArgs: {'name': action.name}),
              style: const TextStyle(fontSize: 16, color: Colors.white, height: 1.4),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildAddMemberCard(AddMemberAction action) {
    final found = _memberSearchResults.isNotEmpty ? _memberSearchResults.first : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: _teal.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: const Icon(Icons.person_add_rounded, color: _teal, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              found != null
                  ? 'voice_entry.add_member_confirm'.tr(namedArgs: {'name': found.name})
                  : _memberSearching
                      ? 'voice_entry.add_member_confirm'.tr(namedArgs: {'name': action.memberNameHint})
                      : 'voice_entry.member_not_found'.tr(namedArgs: {'query': action.memberNameHint}),
              style: TextStyle(
                fontSize: 16,
                color: (!_memberSearching && found == null) ? Colors.redAccent : Colors.white,
                height: 1.4,
              ),
            ),
          ),
          if (_memberSearching)
            const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(color: _teal, strokeWidth: 2),
            ),
        ]),
        if (!_memberSearching && found == null) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _memberSearchCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'voice_entry.member_search_hint'.tr(),
                    hintStyle: const TextStyle(color: Colors.white38),
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
                  onSubmitted: (_) {
                    final q = _memberSearchCtrl.text.trim();
                    if (q.isNotEmpty) _searchMemberForStep(q);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  final q = _memberSearchCtrl.text.trim();
                  if (q.isNotEmpty) _searchMemberForStep(q);
                },
                icon: const Icon(Icons.search_rounded, color: _teal),
                style: IconButton.styleFrom(backgroundColor: _teal.withValues(alpha: 0.15)),
              ),
            ],
          ),
          if (_memberSearchResults.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...(_memberSearchResults.take(3).map((p) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_rounded, color: _teal, size: 20),
              title: Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 14)),
              trailing: const Icon(Icons.check_circle_outline_rounded, color: _teal, size: 18),
              onTap: () => setState(() {
                _memberSearchResults = [p];
                _memberSearchCtrl.clear();
              }),
            ))),
          ],
        ],
      ],
    );
  }

  Widget _buildExpenseCard(AddExpenseAction action) {
    final isIncome    = action.isIncome;
    final amountColor = isIncome ? _teal : _orange;
    final sign        = isIncome ? '+' : '-';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: _orange.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, color: _orange, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$sign${action.currency} ${action.amount.toStringAsFixed(2)} — ${action.description}',
              style: TextStyle(fontSize: 16, color: amountColor, fontWeight: FontWeight.w700),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _Chip(label: action.category, color: _purple),
          if (action.isIncome) _Chip(label: 'Income', color: _teal),
          if (action.splitMode == 'none') _Chip(label: 'No split', color: Colors.white38),
        ]),
      ],
    );
  }

  // ── Shared field widget ───────────────────────────────────────────────────

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
        const SizedBox(height: 60),
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(color: _teal, strokeWidth: 2.5),
        ),
        const SizedBox(height: 20),
        Text(
          'voice_entry.saving'.tr(),
          style: const TextStyle(fontSize: 16, color: Colors.white70),
        ),
        const SizedBox(height: 60),
      ],
    );
  }

  // ── DONE ─────────────────────────────────────────────────────────────────

  Widget _buildDone() {
    return Column(
      children: [
        const SizedBox(height: 48),
        const Icon(Icons.check_circle_rounded, color: _teal, size: 64),
        const SizedBox(height: 16),
        Text(
          'voice_entry.saved'.tr(),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        const SizedBox(height: 48),
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
