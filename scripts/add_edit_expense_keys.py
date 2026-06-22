import json

new_keys = {
    'edit_expense': {
        'unsupported_file_type': {
            'en': 'Unsupported file type. Allowed: images, PDF, TXT, MD.',
            'ru': 'Неподдерживаемый тип файла. Допустимы: изображения, PDF, TXT, MD.',
            'de': 'Nicht unterstützter Dateityp. Erlaubt: Bilder, PDF, TXT, MD.',
            'ka': 'მხარდაუჭერელი ფაილის ტიპი. დასაშვებია: სურათები, PDF, TXT, MD.',
            'fr': 'Type de fichier non supporté. Autorisés : images, PDF, TXT, MD.',
            'es': 'Tipo de archivo no admitido. Permitidos: imágenes, PDF, TXT, MD.',
        },
        'valid_amount': {
            'en': 'Enter a valid amount',
            'ru': 'Введите корректную сумму',
            'de': 'Gib einen gültigen Betrag ein',
            'ka': 'შეიყვანეთ სწორი თანხა',
            'fr': 'Entrez un montant valide',
            'es': 'Ingresa un monto válido',
        },
        'unusually_large': {
            'en': 'Amount is unusually large (>10,000,000). Are you sure?',
            'ru': 'Сумма необычно большая (>10 000 000). Вы уверены?',
            'de': 'Betrag ist ungewöhnlich hoch (>10.000.000). Bist du sicher?',
            'ka': 'თანხა უჩვეულოდ დიდია (>10 000 000). დარწმუნებული ხართ?',
            'fr': 'Le montant est inhabituellement élevé (>10 000 000). Êtes-vous sûr ?',
            'es': 'El monto es inusualmente grande (>10,000,000). ¿Estás seguro?',
        },
        'could_not_get_user': {
            'en': 'Could not get user. Try again.',
            'ru': 'Не удалось получить данные пользователя. Попробуйте снова.',
            'de': 'Benutzer konnte nicht abgerufen werden. Versuche es erneut.',
            'ka': 'მომხმარებლის მიღება ვერ მოხერხდა. სცადეთ ხელახლა.',
            'fr': 'Impossible de récupérer l\'utilisateur. Réessayez.',
            'es': 'No se pudo obtener el usuario. Intenta de nuevo.',
        },
        'percentages_sum': {
            'en': 'Percentages must sum to 100',
            'ru': 'Проценты должны в сумме составлять 100',
            'de': 'Prozentsätze müssen in der Summe 100 ergeben',
            'ka': 'პროცენტების ჯამი უნდა იყოს 100',
            'fr': 'Les pourcentages doivent totaliser 100',
            'es': 'Los porcentajes deben sumar 100',
        },
        'at_least_one_share': {
            'en': 'Enter at least one share',
            'ru': 'Введите хотя бы одну долю',
            'de': 'Gib mindestens einen Anteil ein',
            'ka': 'შეიყვანეთ სულ მცირე ერთი წილი',
            'fr': 'Entrez au moins une part',
            'es': 'Ingresa al menos una parte',
        },
        'colour': {
            'en': 'Colour',
            'ru': 'Цвет',
            'de': 'Farbe',
            'ka': 'ფერი',
            'fr': 'Couleur',
            'es': 'Color',
        },
        'icon': {
            'en': 'Icon',
            'ru': 'Значок',
            'de': 'Symbol',
            'ka': 'ხატი',
            'fr': 'Icône',
            'es': 'Ícono',
        },
    },
    'common': {
        'continue_btn': {
            'en': 'Continue',
            'ru': 'Продолжить',
            'de': 'Weiter',
            'ka': 'გაგრძელება',
            'fr': 'Continuer',
            'es': 'Continuar',
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
