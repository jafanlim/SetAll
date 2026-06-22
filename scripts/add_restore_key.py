import json

translations = {
    'en': 'The group "{group}" was also deleted. What would you like to restore?',
    'ru': 'Группа "{group}" тоже была удалена. Что восстановить?',
    'de': 'Die Gruppe "{group}" wurde ebenfalls gelöscht. Was möchtest du wiederherstellen?',
    'ka': 'ჯგუფი "{group}" ასევე წაიშალა. რის აღდგენა გსურთ?',
    'fr': 'Le groupe "{group}" a également été supprimé. Que souhaitez-vous restaurer ?',
    'es': 'El grupo "{group}" también fue eliminado. ¿Qué deseas restaurar?',
}

for lang, text in translations.items():
    path = f'assets/translations/{lang}.json'
    with open(path) as f:
        d = json.load(f)
    sec = d.get('activity_screen', {})
    if 'restore_group_also_deleted' not in sec:
        sec['restore_group_also_deleted'] = text
        d['activity_screen'] = sec
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(d, f, ensure_ascii=False, indent=2)
        print(f'Added to {lang}.json')
    else:
        print(f'Skipped {lang}.json (already exists)')
