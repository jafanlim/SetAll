import json

new_keys = {
    'wallet_screen': {
        'download_wallet_report': {
            'en': 'Download wallet report', 'ru': 'Скачать отчёт кошелька',
            'de': 'Wallet-Bericht herunterladen', 'ka': 'საფულის ანგარიშის ჩამოტვირთვა',
            'fr': 'Télécharger le rapport du portefeuille', 'es': 'Descargar reporte del monedero',
        },
        'pdf_report_options': {
            'en': 'PDF Report Options', 'ru': 'Параметры PDF-отчёта',
            'de': 'PDF-Berichtsoptionen', 'ka': 'PDF ანგარიშის პარამეტრები',
            'fr': 'Options du rapport PDF', 'es': 'Opciones de reporte PDF',
        },
        'pdf_report_choose': {
            'en': 'Choose what to include in the report', 'ru': 'Выберите, что включить в отчёт',
            'de': 'Wähle aus, was in den Bericht aufgenommen werden soll',
            'ka': 'აირჩიეთ, რა შეიტანოს ანგარიშში',
            'fr': 'Choisissez ce à inclure dans le rapport', 'es': 'Elige qué incluir en el reporte',
        },
        'category_breakdown_option': {
            'en': 'Category breakdown', 'ru': 'Разбивка по категориям',
            'de': 'Kategorienaufschlüsselung', 'ka': 'კატეგორიების დაყოფა',
            'fr': 'Répartition par catégorie', 'es': 'Desglose por categoría',
        },
        'category_breakdown_subtitle': {
            'en': 'Spending by category', 'ru': 'Расходы по категориям',
            'de': 'Ausgaben nach Kategorie', 'ka': 'ხარჯები კატეგორიების მიხედვით',
            'fr': 'Dépenses par catégorie', 'es': 'Gastos por categoría',
        },
        'export_pdf_btn': {
            'en': 'Export PDF', 'ru': 'Экспортировать PDF',
            'de': 'PDF exportieren', 'ka': 'PDF-ის ექსპორტი',
            'fr': 'Exporter PDF', 'es': 'Exportar PDF',
        },
        'loading': {
            'en': 'Loading…', 'ru': 'Загрузка…',
            'de': 'Laden…', 'ka': 'იტვირთება…',
            'fr': 'Chargement…', 'es': 'Cargando…',
        },
    },
    'wallet_entry_detail': {
        'delete_entry_title': {
            'en': 'Delete entry?', 'ru': 'Удалить запись?',
            'de': 'Eintrag löschen?', 'ka': 'ჩანაწერის წაშლა?',
            'fr': 'Supprimer l\'entrée ?', 'es': '¿Eliminar entrada?',
        },
        'delete_entry_body': {
            'en': 'This wallet entry will be permanently removed.',
            'ru': 'Эта запись кошелька будет удалена навсегда.',
            'de': 'Dieser Wallet-Eintrag wird dauerhaft entfernt.',
            'ka': 'ეს საფულის ჩანაწერი სამუდამოდ წაიშლება.',
            'fr': 'Cette entrée du portefeuille sera définitivement supprimée.',
            'es': 'Esta entrada del monedero será eliminada permanentemente.',
        },
        'could_not_open_attachment': {
            'en': 'Could not open attachment', 'ru': 'Не удалось открыть вложение',
            'de': 'Anhang konnte nicht geöffnet werden', 'ka': 'დანართის გახსნა ვერ მოხერხდა',
            'fr': 'Impossible d\'ouvrir la pièce jointe', 'es': 'No se pudo abrir el adjunto',
        },
        'loading': {
            'en': 'Loading…', 'ru': 'Загрузка…',
            'de': 'Laden…', 'ka': 'იტვირთება…',
            'fr': 'Chargement…', 'es': 'Cargando…',
        },
    },
    'auth': {
        'or': {
            'en': 'or', 'ru': 'или',
            'de': 'oder', 'ka': 'ან',
            'fr': 'ou', 'es': 'o',
        },
        'use_face_id': {
            'en': 'Use Face ID to unlock?', 'ru': 'Использовать Face ID для разблокировки?',
            'de': 'Face ID zum Entsperren verwenden?', 'ka': 'გამოიყენოთ Face ID განბლოკვისთვის?',
            'fr': 'Utiliser Face ID pour déverrouiller ?', 'es': '¿Usar Face ID para desbloquear?',
        },
        'not_now': {
            'en': 'Not now', 'ru': 'Не сейчас',
            'de': 'Nicht jetzt', 'ka': 'არა ახლა',
            'fr': 'Pas maintenant', 'es': 'Ahora no',
        },
        'enable': {
            'en': 'Enable', 'ru': 'Включить',
            'de': 'Aktivieren', 'ka': 'ჩართვა',
            'fr': 'Activer', 'es': 'Activar',
        },
        'stay_on_login': {
            'en': 'Stay on Login', 'ru': 'Остаться на экране входа',
            'de': 'Auf Anmeldeseite bleiben', 'ka': 'შესვლის გვერდზე დარჩენა',
            'fr': 'Rester sur la connexion', 'es': 'Quedarse en inicio de sesión',
        },
        'create_account': {
            'en': 'Create Account', 'ru': 'Создать аккаунт',
            'de': 'Konto erstellen', 'ka': 'ანგარიშის შექმნა',
            'fr': 'Créer un compte', 'es': 'Crear cuenta',
        },
        'continue_google': {
            'en': 'Continue with Google', 'ru': 'Продолжить с Google',
            'de': 'Mit Google fortfahren', 'ka': 'Google-ით გაგრძელება',
            'fr': 'Continuer avec Google', 'es': 'Continuar con Google',
        },
        'continue_apple': {
            'en': 'Continue with Apple', 'ru': 'Продолжить с Apple',
            'de': 'Mit Apple fortfahren', 'ka': 'Apple-ით გაგრძელება',
            'fr': 'Continuer avec Apple', 'es': 'Continuar con Apple',
        },
    },
    'register_screen': {
        'already_have_account': {
            'en': 'Already have an account? ', 'ru': 'Уже есть аккаунт? ',
            'de': 'Bereits ein Konto? ', 'ka': 'უკვე გაქვთ ანგარიში? ',
            'fr': 'Déjà un compte ? ', 'es': '¿Ya tienes una cuenta? ',
        },
    },
    'edit_group': {
        'choose_gallery': {
            'en': 'Choose from Gallery', 'ru': 'Выбрать из галереи',
            'de': 'Aus Galerie auswählen', 'ka': 'გალერიიდან არჩევა',
            'fr': 'Choisir dans la galerie', 'es': 'Elegir de la galería',
        },
        'take_photo': {
            'en': 'Take a Photo', 'ru': 'Сделать снимок',
            'de': 'Foto aufnehmen', 'ka': 'ფოტოს გადაღება',
            'fr': 'Prendre une photo', 'es': 'Tomar una foto',
        },
        'remove_photo': {
            'en': 'Remove Photo', 'ru': 'Удалить фото',
            'de': 'Foto entfernen', 'ka': 'ფოტოს წაშლა',
            'fr': 'Supprimer la photo', 'es': 'Eliminar foto',
        },
        'name_empty': {
            'en': 'Group name cannot be empty', 'ru': 'Название группы не может быть пустым',
            'de': 'Gruppenname darf nicht leer sein', 'ka': 'ჯგუფის სახელი არ შეიძლება იყოს ცარიელი',
            'fr': 'Le nom du groupe ne peut pas être vide', 'es': 'El nombre del grupo no puede estar vacío',
        },
        'group_updated': {
            'en': 'Group updated', 'ru': 'Группа обновлена',
            'de': 'Gruppe aktualisiert', 'ka': 'ჯგუფი განახლდა',
            'fr': 'Groupe mis à jour', 'es': 'Grupo actualizado',
        },
        'pick_colour': {
            'en': 'Pick a colour', 'ru': 'Выберите цвет',
            'de': 'Farbe auswählen', 'ka': 'აირჩიეთ ფერი',
            'fr': 'Choisir une couleur', 'es': 'Elige un color',
        },
    },
    'friends': {
        'add_friend': {
            'en': 'Add friend', 'ru': 'Добавить друга',
            'de': 'Freund hinzufügen', 'ka': 'მეგობრის დამატება',
            'fr': 'Ajouter un ami', 'es': 'Agregar amigo',
        },
        'add': {
            'en': 'Add', 'ru': 'Добавить',
            'de': 'Hinzufügen', 'ka': 'დამატება',
            'fr': 'Ajouter', 'es': 'Agregar',
        },
    },
    'common': {
        'done': {
            'en': 'Done', 'ru': 'Готово',
            'de': 'Fertig', 'ka': 'მზადაა',
            'fr': 'Terminé', 'es': 'Listo',
        },
        'loading': {
            'en': 'Loading…', 'ru': 'Загрузка…',
            'de': 'Laden…', 'ka': 'იტვირთება…',
            'fr': 'Chargement…', 'es': 'Cargando…',
        },
        'add': {
            'en': 'Add', 'ru': 'Добавить',
            'de': 'Hinzufügen', 'ka': 'დამატება',
            'fr': 'Ajouter', 'es': 'Agregar',
        },
    },
    'expenses': {
        'mic_permission': {
            'en': 'Microphone permission required', 'ru': 'Требуется разрешение на микрофон',
            'de': 'Mikrofonberechtigung erforderlich', 'ka': 'საჭიროა მიკროფონის ნებართვა',
            'fr': 'Permission du microphone requise', 'es': 'Se requiere permiso del micrófono',
        },
    },
    'add_expense': {
        'done': {
            'en': 'Done', 'ru': 'Готово',
            'de': 'Fertig', 'ka': 'მზადაა',
            'fr': 'Terminé', 'es': 'Listo',
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
