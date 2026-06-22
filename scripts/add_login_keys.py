import json

new_keys = {
    'auth': {
        'face_id_content': {
            'en': 'Next time you open the app, you can unlock with Face ID instead of entering your password.',
            'ru': 'При следующем открытии приложения вы сможете разблокировать его с помощью Face ID.',
            'de': 'Beim nächsten Öffnen der App kannst du mit Face ID entsperren.',
            'ka': 'შემდეგ ჯერ Face ID-ით განბლოკვა შეგიძლიათ.',
            'fr': "La prochaine fois, déverrouillez avec Face ID.",
            'es': 'La próxima vez podrás desbloquear con Face ID.',
        },
    },
    'groups_screen': {
        'force_delete_group_title': {
            'en': 'Force delete group?',
            'ru': 'Принудительно удалить группу?',
            'de': 'Gruppe erzwungen löschen?',
            'ka': 'ჯგუფის იძულებითი წაშლა?',
            'fr': 'Suppression forcée du groupe ?',
            'es': '¿Forzar eliminación del grupo?',
        },
        'force_delete_group_body': {
            'en': 'Force-delete "{name}"? This will also purge all its expenses from the server.',
            'ru': 'Принудительно удалить "{name}"? Все расходы группы будут удалены с сервера.',
            'de': '"{name}" erzwungen löschen? Alle Ausgaben werden vom Server gelöscht.',
            'ka': '"{name}" იძულებით წაიშლება? ყველა ხარჯი სერვერიდანაც წაიშლება.',
            'fr': 'Forcer la suppression de "{name}" ? Toutes ses dépenses seront purgées du serveur.',
            'es': '¿Forzar la eliminación de "{name}"? Todos sus gastos también serán eliminados del servidor.',
        },
        'delete_group_body': {
            'en': 'Delete "{name}"? You can restore it from the Activity screen within 12 months.',
            'ru': 'Удалить "{name}"? Вы сможете восстановить её из экрана активности в течение 12 месяцев.',
            'de': '"{name}" löschen? Du kannst es innerhalb von 12 Monaten im Aktivitätsbildschirm wiederherstellen.',
            'ka': '"{name}" წაიშლება? 12 თვის განმავლობაში შეგიძლიათ აღადგინოთ Activity-დან.',
            'fr': 'Supprimer "{name}" ? Vous pouvez le restaurer depuis l\'écran Activité dans les 12 mois.',
            'es': '¿Eliminar "{name}"? Puedes restaurarlo desde la pantalla de Actividad en 12 meses.',
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
