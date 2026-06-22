import json

new_keys = {
    'no_results': {
        'en': 'No results',
        'ru': 'Нет результатов',
        'de': 'Keine Ergebnisse',
        'ka': 'შედეგი არ მოიძებნა',
        'fr': 'Aucun résultat',
        'es': 'Sin resultados',
    },
    'no_results_hint': {
        'en': 'Try a different search term or filter.',
        'ru': 'Попробуйте другой поисковый запрос или фильтр.',
        'de': 'Versuche einen anderen Suchbegriff oder Filter.',
        'ka': 'სცადეთ სხვა საძიებო სიტყვა ან ფილტრი.',
        'fr': 'Essayez un autre terme de recherche ou filtre.',
        'es': 'Intenta con otro término de búsqueda o filtro.',
    },
    'deleted_tag': {
        'en': 'Deleted',
        'ru': 'Удалено',
        'de': 'Gelöscht',
        'ka': 'წაშლილია',
        'fr': 'Supprimé',
        'es': 'Eliminado',
    },
}

for lang in ['en', 'ru', 'de', 'ka', 'fr', 'es']:
    path = f'assets/translations/{lang}.json'
    with open(path) as f:
        d = json.load(f)
    sec = d.get('activity_screen', {})
    added = []
    for key, translations in new_keys.items():
        if key not in sec:
            sec[key] = translations[lang]
            added.append(key)
    d['activity_screen'] = sec
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
    print(f'{lang}.json: added {added}')
