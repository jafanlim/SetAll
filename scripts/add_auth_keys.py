import json

new_keys = {
    'auth': {
        'recovery_email_sent': {
            'en': 'Recovery email sent to {email}',
            'ru': 'Письмо для восстановления отправлено на {email}',
            'de': 'Wiederherstellungs-E-Mail wurde an {email} gesendet',
            'ka': 'აღდგენის წერილი გაიგზავნა {email}-ზე',
            'fr': 'E-mail de récupération envoyé à {email}',
            'es': 'Correo de recuperación enviado a {email}',
        },
        'back': {
            'en': 'Back',
            'ru': 'Назад',
            'de': 'Zurück',
            'ka': 'უკან',
            'fr': 'Retour',
            'es': 'Volver',
        },
        'try_again_label': {
            'en': 'Try {label} again',
            'ru': 'Попробуйте {label} снова',
            'de': '{label} erneut versuchen',
            'ka': 'სცადეთ {label} ხელახლა',
            'fr': 'Réessayer {label}',
            'es': 'Reintentar {label}',
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
