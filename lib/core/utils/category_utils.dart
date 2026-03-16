import 'package:easy_localization/easy_localization.dart';

const _categoryKeyMap = {
  'General':          'categories.general',
  'Food & drink':     'categories.food_drink',
  'Transport':        'categories.transport',
  'Entertainment':    'categories.entertainment',
  'Bills & utilities':'categories.bills_utilities',
  'Shopping':         'categories.shopping',
  'Travel':           'categories.travel',
  'Other':            'categories.other',
};

/// Returns the localized display name for a stored category string.
/// Falls back to the original string for user-created categories.
String categoryTr(String category) {
  final key = _categoryKeyMap[category];
  return key != null ? key.tr() : category;
}
