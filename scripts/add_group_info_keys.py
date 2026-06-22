import json

new_keys = {
    'groups_screen': {
        'could_not_delete_soft': {
            'en': 'Could not delete. Try Force Delete from the \u2026 menu.',
            'ru': 'Не удалось удалить. Попробуйте «Принудительное удаление» в меню \u2026',
            'de': 'Löschen fehlgeschlagen. Versuche \"Force Delete\" im \u2026 Menü.',
            'ka': 'წაშლა ვერ მოხერხდა. სცადეთ Force Delete \u2026 მენიუდან.',
            'fr': 'Impossible de supprimer. Essayez \"Suppression forcée\" dans le menu \u2026',
            'es': 'No se pudo eliminar. Intenta \"Forzar eliminación\" en el menú \u2026',
        },
        'settle_body_group': {
            'en': 'Mark "{name}" as settled? All debts will show as zero.',
            'ru': 'Отметить "{name}" как урегулированную? Все долги будут обнулены.',
            'de': '"{name}" als beglichen markieren? Alle Schulden werden auf null gesetzt.',
            'ka': 'მოინიშნოს "{name}" დასრულებულად? ყველა ვალი ნულამდე დაიყვანება.',
            'fr': 'Marquer "{name}" comme réglé ? Toutes les dettes seront mises à zéro.',
            'es': '¿Marcar "{name}" como saldado? Todas las deudas se mostrarán en cero.',
        },
        'force_delete_label': {
            'en': 'Force Delete',
            'ru': 'Принудительное удаление',
            'de': 'Erzwungenes Löschen',
            'ka': 'იძულებითი წაშლა',
            'fr': 'Suppression forcée',
            'es': 'Forzar eliminación',
        },
        'export_failed_detail': {
            'en': 'Export failed: {error}',
            'ru': 'Ошибка экспорта: {error}',
            'de': 'Export fehlgeschlagen: {error}',
            'ka': 'ექსპორტი ვერ მოხერხდა: {error}',
            'fr': 'Échec de l\'export : {error}',
            'es': 'Error de exportación: {error}',
        },
    },
    'common': {
        'add': {
            'en': 'Add',
            'ru': 'Добавить',
            'de': 'Hinzufügen',
            'ka': 'დამატება',
            'fr': 'Ajouter',
            'es': 'Agregar',
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
