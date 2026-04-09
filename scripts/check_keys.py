import json

d = json.load(open('assets/translations/en.json'))

needed = {
    'activity_screen': ['you_deleted', 'wallet_income_tag', 'wallet_tag', 'restore_btn', 'you_settled', 'settled_by'],
    'group_detail': [
        'delete_expenses_title', 'delete_expenses_confirm', 'delete_expenses_confirm_plural',
        'could_not_delete_expenses', 'rename_group', 'group_name_label', 'could_not_rename',
        'settle_title', 'settle_body', 'settled_snack', 'settle_failed',
        'reopen_title', 'reopen_body', 'reopened_snack', 'reopen_failed',
        'delete_title', 'delete_body', 'delete_sure_title', 'delete_sure_body',
        'could_not_delete', 'deselect_all', 'select_all', 'edit_group', 'select_expenses',
        'settle_group', 'reopen_group', 'delete_group', 'invite_member', 'members',
        'expenses', 'add_expense',
    ],
    'groups_screen': [
        'group_name_hint', 'settle_body', 'delete_group', 'force_delete_group_title',
        'force_delete_group_body', 'delete_group_body', 'reopen_group',
        'download_group_report', 'export_failed', 'edit_expense',
        'delete_expense_title', 'delete_expense_body', 'expense_deleted',
    ],
    'expense_detail': [
        'delete_title', 'delete_body', 'delete_sure_title', 'delete_sure_body',
        'yes_delete_forever', 'expense_deleted', 'you', 'member', 'edit', 'delete',
    ],
}

for section, keys in needed.items():
    sec = d.get(section, {})
    missing = [k for k in keys if k not in sec]
    if missing:
        print(f'MISSING in {section}: {missing}')
    else:
        print(f'OK: {section}')
