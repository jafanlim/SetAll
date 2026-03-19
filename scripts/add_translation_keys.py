import json

translations = {
    'en': {
        'amount_unusually_large': 'Amount exceeds $10,000,000 — is this correct?',
        'continue_anyway': 'Continue',
    },
    'ru': {
        'amount_unusually_large': 'Сумма превышает $10,000,000 — вы уверены?',
        'continue_anyway': 'Продолжить',
    },
    'de': {
        'amount_unusually_large': 'Betrag übersteigt $10.000.000 — ist das korrekt?',
        'continue_anyway': 'Fortfahren',
    },
    'es': {
        'amount_unusually_large': 'El monto supera $10,000,000 — ¿es correcto?',
        'continue_anyway': 'Continuar',
    },
    'fr': {
        'amount_unusually_large': 'Le montant dépasse $10 000 000 — est-ce correct?',
        'continue_anyway': 'Continuer',
    },
    'ka': {
        'amount_unusually_large': 'თანხა აღემატება $10,000,000 — დარწმუნებული ხართ?',
        'continue_anyway': 'გაგრძელება',
    },
}

for lang, keys in translations.items():
    path = f'assets/translations/{lang}.json'
    with open(path, encoding='utf-8') as f:
        d = json.load(f)
    d.setdefault('add_expense', {})['amount_unusually_large'] = keys['amount_unusually_large']
    d.setdefault('common', {})['continue_anyway'] = keys['continue_anyway']
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
    print(f'Updated {lang}.json')
