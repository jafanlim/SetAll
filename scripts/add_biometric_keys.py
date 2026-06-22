import json

new_keys = {
    'auth': {
        'checking': {
            'en': 'Checking…',
            'ru': 'Проверка…',
            'de': 'Prüfung…',
            'ka': 'შემოწმება…',
            'fr': 'Vérification…',
            'es': 'Verificando…',
        },
        'unlock_with': {
            'en': 'Unlock with {label}',
            'ru': 'Разблокировать с помощью {label}',
            'de': 'Mit {label} entsperren',
            'ka': '{label}-ით განბლოკვა',
            'fr': 'Déverrouiller avec {label}',
            'es': 'Desbloquear con {label}',
        },
    },
}

for lang in ['en', 'ru', 'de', 'ka', 'fr', 'es']:
    path = f'assets/translations/{lang}.json'
    with open(path) as f:
        d = json.load(f)
    for section, keys in new_keys.items():
        sec = d.get(section, {})
        added = []
        for key, translations in keys.items():
            if key not in sec:
                sec[key] = translations[lang]
                added.append(key)
        d[section] = sec
        if added:
            print(f'{lang}.json [{section}]: added {added}')
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
