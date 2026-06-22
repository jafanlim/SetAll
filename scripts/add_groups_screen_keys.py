import json

new_keys = {
    'groups_screen': {
        'download_groups_report': {
            'en': 'Download groups report',
            'ru': 'Скачать отчёт по группам',
            'de': 'Gruppenberichte herunterladen',
            'ka': 'ჯგუფების ანგარიშის ჩამოტვირთვა',
            'fr': 'Télécharger le rapport des groupes',
            'es': 'Descargar reporte de grupos',
        },
        'settled_up_tag': {
            'en': 'Settled up',
            'ru': 'Расчёты завершены',
            'de': 'Abgerechnet',
            'ka': 'დასრულებულია',
            'fr': 'Soldé',
            'es': 'Saldado',
        },
    },
    'export': {
        'export_failed_detail': {
            'en': 'Export failed: {error}',
            'ru': 'Ошибка экспорта: {error}',
            'de': 'Export fehlgeschlagen: {error}',
            'ka': 'ექსპორტი ვერ მოხერხდა: {error}',
            'fr': "Échec de l'export : {error}",
            'es': 'Error de exportación: {error}',
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
