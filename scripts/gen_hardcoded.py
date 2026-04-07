import re, csv, os

screens = [
  'lib/features/dashboard/presentation/screens/dashboard_screen.dart',
  'lib/features/groups/presentation/screens/groups_screen.dart',
  'lib/features/wallet/presentation/screens/wallet_screen.dart',
  'lib/features/settings/presentation/screens/settings_screen.dart',
  'lib/features/activity/presentation/screens/activity_screen.dart',
  'lib/features/voice/presentation/voice_entry_sheet.dart',
  'lib/features/groups/presentation/screens/group_info_screen.dart',
]

pattern = re.compile(r"""Text\(['"]([^'"]{2,})['"]\)(?!\s*\.tr)""")
rows = []
for path in screens:
    if not os.path.exists(path):
        continue
    screen = os.path.basename(path).replace('.dart', '')
    for i, line in enumerate(open(path, encoding='utf-8'), 1):
        for m in pattern.finditer(line):
            val = m.group(1).strip()
            if val and not val.startswith('/'):
                rows.append([screen, i, val])

with open('hardcoded_strings.csv', 'w', newline='', encoding='utf-8') as f:
    w = csv.writer(f)
    w.writerow(['screen', 'line', 'hardcoded_text'])
    w.writerows(rows)

print(f'hardcoded_strings.csv: {len(rows)} entries')
