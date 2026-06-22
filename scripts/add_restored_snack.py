import json

translations = {
    'en': '"{name}" restored',
    'ru': '"{name}" восстановлено',
    'de': '"{name}" wiederhergestellt',
    'ka': '"{name}" აღდგენილია',
    'fr': '"{name}" restauré',
    'es': '"{name}" restaurado',
}

for lang, text in translations.items():
    path = f'assets/translations/{lang}.json'
    with open(path) as f:
        d = json.load(f)
    sec = d.get('activity_screen', {})
    if 'restored_snack' not in sec:
        sec['restored_snack'] = text
        d['activity_screen'] = sec
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(d, f, ensure_ascii=False, indent=2)
        print(f'Added to {lang}.json')
    else:
        print(f'Skipped {lang}.json (already exists)')
