/**
 * SetAll Website Localisation
 * Supports: en, de, ru, ka, fr, es
 * Usage: add data-i18n="key" to any element; HTML content uses data-i18n-html="key"
 * Language auto-detected from browser; override with setAllLang('de') or ?lang=de
 */
(function () {
  'use strict';

  const LANGS = ['en', 'de', 'ru', 'ka', 'fr', 'es'];
  const LANG_LABELS = { en: 'EN', de: 'DE', ru: 'RU', ka: 'KA', fr: 'FR', es: 'ES' };
  const LANG_NAMES  = { en: 'English', de: 'Deutsch', ru: 'Русский', ka: 'ქართული', fr: 'Français', es: 'Español' };

  const T = {
    en: {
      nav_download:   'Download',
      nav_sign_in:    'Sign In',
      beta_text:      'SetAll is in public beta — features may change.',
      beta_feedback:  'Share feedback →',
      beta_dismiss:   'Dismiss',
      hero_eyebrow:   'Public Beta · Greedy Flow Engine',
      hero_h1:        'Stop Letting <span class="text-gradient">Money</span> Stall Your Life',
      hero_sub:       'The moment you pay for a group, SetAll splits it, tracks it, and settles it — across currencies, across borders, in real time. No chasing. No awkward texts. No stale debts.',
      hero_cta_portal:'Open Portal',
      hero_cta_web:   'Web App',
      hero_cta_dl:    'Download App',
      hero_scroll:    'Scroll',
      proof_currencies:'Currencies',
      proof_sync:     'Sync',
      proof_local:    'Local First',
      proof_platforms:'Platforms',
      feat_label:     'Why SetAll',
      feat_title:     'Built for people who <em>move</em>',
      feat_body:      'Trips with friends, dinners with colleagues, shared subscriptions — SetAll was designed for every financial entanglement that modern life throws at you. No spreadsheet needed.',
      feat1_title:    'Multi-Currency, Natively',
      feat1_body:     'Pay in AED, split in USD, settle in EUR — live exchange rates do the maths so you never argue about conversions again.',
      feat2_title:    'Real-Time Ledger',
      feat2_body:     'Every tap syncs instantly across every device in your group. The moment an expense lands, everyone sees it.',
      feat3_title:    'Smart Group Splits',
      feat3_body:     'Equal, percentage, itemised — pick how you split. SetAll remembers preferences so repeat groups work on autopilot.',
      feat4_title:    'Insights Hub',
      feat4_body:     'An AI-powered canvas that turns your expense data into visual patterns. Understand spending before it becomes a problem.',
      feat5_title:    'Secure by Design',
      feat5_body:     'End-to-end auth, row-level security on every data row. Your financial history is yours — not ours to monetise.',
      feat6_title:    'Every Platform',
      feat6_body:     'iOS, Android, macOS, Windows, Web — your ledger travels with you. Native performance on every OS.',
      greedy_label:   'The Greedy Flow',
      greedy_title:   'Every Rupee. Every Dirham.<br>Accounted For.',
      greedy_body:    "Life doesn't pause for currency tables. SetAll's Greedy Flow algorithm greedily minimises the number of transactions needed to settle any group — no matter how tangled the web, no matter how many currencies are in play. One pass. Optimal result.",
      greedy_cta:     'Open Portal',
      how_label:      'How it works',
      how_title:      'Three steps to zero debt',
      step1_title:    'Create a group',
      step1_body:     'Name it "Bali Trip", "Flat Bills" or anything else. Invite members by email or link — they\'re in in seconds.',
      step2_title:    'Log expenses as they happen',
      step2_body:     'Add an expense from any device. Choose who paid, who owes, in which currency. SetAll converts and records in real time.',
      step3_title:    'Settle with one tap',
      step3_body:     'The Greedy Flow engine collapses all debts into the fewest possible payments. Mark settled, done.',
      platform_ios:   'iOS & macOS',
      platform_android:'Android',
      platform_windows:'Windows',
      platform_web:   'Web App',
      cta_label:      'Get Started',
      cta_title:      'Built for the modern world.<br>Available everywhere.',
      cta_body:       'Native apps for iOS, Android, macOS, and Windows — plus a full-featured web portal. Your ledger, wherever you are.',
      cta_portal:     'Open Portal',
      cta_download:   'Download the App',
      footer_privacy: 'Privacy Policy',
      footer_terms:   'Terms of Service',
      footer_help:    'Help & Support',
      footer_contact: 'Contact',
    },
    de: {
      nav_download:   'Herunterladen',
      nav_sign_in:    'Anmelden',
      beta_text:      'SetAll befindet sich in der öffentlichen Beta — Funktionen können sich ändern.',
      beta_feedback:  'Feedback geben →',
      beta_dismiss:   'Schließen',
      hero_eyebrow:   'Öffentliche Beta · Greedy Flow Engine',
      hero_h1:        'Lass <span class="text-gradient">Geld</span> dein Leben nicht aufhalten',
      hero_sub:       'In dem Moment, in dem du für eine Gruppe bezahlst, teilt, verfolgt und begleicht SetAll es — über Währungen, über Grenzen, in Echtzeit. Kein Nachjagen. Keine unangenehmen Nachrichten. Keine veralteten Schulden.',
      hero_cta_portal:'Portal öffnen',
      hero_cta_web:   'Web-App',
      hero_cta_dl:    'App herunterladen',
      hero_scroll:    'Scrollen',
      proof_currencies:'Währungen',
      proof_sync:     'Synchronisation',
      proof_local:    'Lokal-Zuerst',
      proof_platforms:'Plattformen',
      feat_label:     'Warum SetAll',
      feat_title:     'Gebaut für Menschen, die sich <em>bewegen</em>',
      feat_body:      'Reisen mit Freunden, Abendessen mit Kollegen, geteilte Abonnements — SetAll wurde für jede finanzielle Verstrickung des modernen Lebens entworfen. Kein Tabellenblatt nötig.',
      feat1_title:    'Mehrwährung, nativ',
      feat1_body:     'In AED zahlen, in USD aufteilen, in EUR begleichen — Live-Wechselkurse erledigen die Mathematik, sodass du nie wieder über Umrechnungen streitest.',
      feat2_title:    'Echtzeit-Ledger',
      feat2_body:     'Jeder Tap synchronisiert sofort auf jedem Gerät in deiner Gruppe. In dem Moment, in dem eine Ausgabe eingeht, sehen alle sie.',
      feat3_title:    'Smarte Gruppenaufteilungen',
      feat3_body:     'Gleich, prozentual, aufgeteilt — wähle, wie du aufteilst. SetAll merkt sich Präferenzen, sodass Wiederholungsgruppen automatisch funktionieren.',
      feat4_title:    'Insights Hub',
      feat4_body:     'Ein KI-gestütztes Canvas, das deine Ausgabendaten in visuelle Muster verwandelt. Ausgaben verstehen, bevor sie zum Problem werden.',
      feat5_title:    'Sicherheit by Design',
      feat5_body:     'Ende-zu-Ende-Authentifizierung, Zeilensicherheit auf jeder Datenzeile. Deine Finanzhistorie gehört dir — nicht uns zum Monetarisieren.',
      feat6_title:    'Jede Plattform',
      feat6_body:     'iOS, Android, macOS, Windows, Web — dein Ledger reist mit dir. Native Performance auf jedem Betriebssystem.',
      greedy_label:   'Der Greedy Flow',
      greedy_title:   'Jede Rupie. Jeder Dirham.<br>Alles erfasst.',
      greedy_body:    "Das Leben macht keine Pause für Währungstabellen. SetAlls Greedy Flow-Algorithmus minimiert die Transaktionen zum Begleichen jeder Gruppe — egal wie verworren das Netz, egal wie viele Währungen im Spiel sind. Ein Durchlauf. Optimales Ergebnis.",
      greedy_cta:     'Portal öffnen',
      how_label:      'So funktioniert es',
      how_title:      'Drei Schritte bis zu null Schulden',
      step1_title:    'Gruppe erstellen',
      step1_body:     'Nenn sie "Bali-Reise", "Wohnungsrechnungen" oder sonst etwas. Lade Mitglieder per E-Mail oder Link ein — sie sind in Sekunden dabei.',
      step2_title:    'Ausgaben live erfassen',
      step2_body:     'Füge eine Ausgabe von jedem Gerät hinzu. Wähle, wer bezahlt hat, wer schuldet, in welcher Währung. SetAll konvertiert und erfasst in Echtzeit.',
      step3_title:    'Mit einem Tap begleichen',
      step3_body:     'Der Greedy Flow-Motor reduziert alle Schulden auf die wenigstmöglichen Zahlungen. Als beglichen markieren, fertig.',
      platform_ios:   'iOS & macOS',
      platform_android:'Android',
      platform_windows:'Windows',
      platform_web:   'Web-App',
      cta_label:      'Loslegen',
      cta_title:      'Für die moderne Welt gebaut.<br>Überall verfügbar.',
      cta_body:       'Native Apps für iOS, Android, macOS und Windows — plus ein vollständiges Web-Portal. Dein Ledger, wo auch immer du bist.',
      cta_portal:     'Portal öffnen',
      cta_download:   'App herunterladen',
      footer_privacy: 'Datenschutzrichtlinie',
      footer_terms:   'Nutzungsbedingungen',
      footer_help:    'Hilfe & Support',
      footer_contact: 'Kontakt',
    },
    ru: {
      nav_download:   'Скачать',
      nav_sign_in:    'Войти',
      beta_text:      'SetAll находится в открытой бета-версии — возможны изменения.',
      beta_feedback:  'Оставить отзыв →',
      beta_dismiss:   'Закрыть',
      hero_eyebrow:   'Открытая Бета · Greedy Flow Engine',
      hero_h1:        'Не давай <span class="text-gradient">деньгам</span> останавливать твою жизнь',
      hero_sub:       'Как только ты платишь за группу, SetAll делит, отслеживает и рассчитывает — через валюты, через границы, в реальном времени. Никаких напоминаний. Никаких неловких сообщений. Никаких устаревших долгов.',
      hero_cta_portal:'Открыть портал',
      hero_cta_web:   'Веб-приложение',
      hero_cta_dl:    'Скачать приложение',
      hero_scroll:    'Вниз',
      proof_currencies:'Валют',
      proof_sync:     'Синхронизация',
      proof_local:    'Локально-первый',
      proof_platforms:'Платформы',
      feat_label:     'Почему SetAll',
      feat_title:     'Создан для тех, кто <em>в движении</em>',
      feat_body:      'Поездки с друзьями, ужины с коллегами, общие подписки — SetAll создан для каждого финансового запутывания, которое бросает современная жизнь. Никаких таблиц.',
      feat1_title:    'Мультивалютность, нативно',
      feat1_body:     'Плати в AED, делись в USD, рассчитывайся в EUR — живые курсы делают математику, чтобы ты больше никогда не спорил о конвертациях.',
      feat2_title:    'Реальный учёт',
      feat2_body:     'Каждое действие синхронизируется мгновенно на каждом устройстве в твоей группе. Как только расход появляется, все его видят.',
      feat3_title:    'Умное разделение',
      feat3_body:     'Поровну, по процентам, по статьям — выбирай как делить. SetAll запоминает предпочтения, так что повторяющиеся группы работают автоматически.',
      feat4_title:    'Аналитический центр',
      feat4_body:     'ИИ-канвас, превращающий данные о расходах в визуальные паттерны. Понимай расходы до того, как они станут проблемой.',
      feat5_title:    'Безопасность в основе',
      feat5_body:     'Сквозная аутентификация, безопасность на уровне строк для каждой записи. Твоя финансовая история — твоя, а не наша для монетизации.',
      feat6_title:    'Каждая платформа',
      feat6_body:     'iOS, Android, macOS, Windows, Web — твой учёт путешествует с тобой. Нативная производительность на каждой ОС.',
      greedy_label:   'Greedy Flow',
      greedy_title:   'Каждая рупия. Каждый дирхам.<br>Всё учтено.',
      greedy_body:    "Жизнь не делает паузы для таблиц курсов. Алгоритм Greedy Flow в SetAll жадно минимизирует количество транзакций для урегулирования любой группы — независимо от запутанности долгов и числа валют. Один проход. Оптимальный результат.",
      greedy_cta:     'Открыть портал',
      how_label:      'Как это работает',
      how_title:      'Три шага до нулевого долга',
      step1_title:    'Создай группу',
      step1_body:     'Назови её «Поездка на Бали», «Счета за квартиру» или что-то другое. Пригласи участников по email или ссылке — они вступают за секунды.',
      step2_title:    'Вноси расходы в момент',
      step2_body:     'Добавь расход с любого устройства. Выбери кто заплатил, кто должен, в какой валюте. SetAll конвертирует и записывает в реальном времени.',
      step3_title:    'Рассчитайся одним нажатием',
      step3_body:     'Движок Greedy Flow сводит все долги к минимальному числу платежей. Отметь как оплаченное — готово.',
      platform_ios:   'iOS и macOS',
      platform_android:'Android',
      platform_windows:'Windows',
      platform_web:   'Веб-приложение',
      cta_label:      'Начать',
      cta_title:      'Создан для современного мира.<br>Доступен везде.',
      cta_body:       'Нативные приложения для iOS, Android, macOS и Windows — плюс полноценный веб-портал. Твой учёт, где бы ты ни был.',
      cta_portal:     'Открыть портал',
      cta_download:   'Скачать приложение',
      footer_privacy: 'Политика конфиденциальности',
      footer_terms:   'Условия использования',
      footer_help:    'Помощь и поддержка',
      footer_contact: 'Контакт',
    },
    ka: {
      nav_download:   'ჩამოტვირთვა',
      nav_sign_in:    'შესვლა',
      beta_text:      'SetAll საჯარო ბეტა-ვერსიაშია — ფუნქციები შეიძლება შეიცვალოს.',
      beta_feedback:  'გამოხმაურება →',
      beta_dismiss:   'დახურვა',
      hero_eyebrow:   'საჯარო ბეტა · Greedy Flow Engine',
      hero_h1:        'ნუ მისცემ <span class="text-gradient">ფულს</span> შენი ცხოვრების შეჩერების საშუალებას',
      hero_sub:       'მას შემდეგ რაც გადაიხდი ჯგუფისთვის, SetAll ყოფს, თვალს ადევნებს და ანაზღაურებს — ვალუტებზე, საზღვრებზე, რეალურ დროში. გამოდევნება — არ. გაუბედავი შეტყობინებები — არ. ძველი ვალები — არ.',
      hero_cta_portal:'პორტალის გახსნა',
      hero_cta_web:   'ვებ-აპლიკაცია',
      hero_cta_dl:    'აპლიკაციის ჩამოტვირთვა',
      hero_scroll:    'გადაახვიე',
      proof_currencies:'ვალუტა',
      proof_sync:     'სინქრონიზაცია',
      proof_local:    'ლოკალური-პირველი',
      proof_platforms:'პლატფორმა',
      feat_label:     'რატომ SetAll',
      feat_title:     'შექმნილია <em>მოძრავი</em> ადამიანებისთვის',
      feat_body:      'მოგზაურობები მეგობრებთან, სადილები კოლეგებთან, საერთო გამოწერები — SetAll შეიქმნა თანამედროვე ცხოვრების ყველა ფინანსური გართულებისთვის. ცხრილის გარეშე.',
      feat1_title:    'მრავალვალუტობა, ნათელი',
      feat1_body:     'გადაიხადე AED-ში, გაიყავი USD-ში, ანაზღაურე EUR-ში — ცოცხალი გაცვლითი კურსები ითვლიან, ასე რომ კონვერტაციებზე კამათი გამქრალია.',
      feat2_title:    'რეალური დროის ჩანაწერი',
      feat2_body:     'ყოველი შეხება სინქრონიზდება მყისიერად ჯგუფის ყოველ მოწყობილობაზე. ხარჯის დამატებისთანავე ყველა ხედავს.',
      feat3_title:    'ჭკვიანი ჯგუფური გაყოფა',
      feat3_body:     'თანაბრად, პროცენტით, ცალ-ცალკე — აირჩიე გაყოფის გზა. SetAll ახსოვს პრეფერენციები, ასე რომ განმეორებადი ჯგუფები ავტომატურად მუშაობს.',
      feat4_title:    'ანალიტიკის ცენტრი',
      feat4_body:     'ხელოვნური ინტელექტის ტილო, რომელიც ხარჯის მონაცემებს ვიზუალურ შაბლონებად აქცევს. გაიგე ხარჯები, სანამ პრობლემა გახდება.',
      feat5_title:    'უსაფრთხოება გზამკვლევად',
      feat5_body:     'ბოლო-ბოლო ავთენტიფიკაცია, სტრიქონის დონის უსაფრთხოება ყოველ მონაცემზე. შენი ფინანსური ისტორია შენია — არ ვმონეტიზებთ.',
      feat6_title:    'ყველა პლატფორმა',
      feat6_body:     'iOS, Android, macOS, Windows, Web — შენი ჩანაწერი გაყვება. ნათელი შესრულება ყოველ ოპერაციულ სისტემაზე.',
      greedy_label:   'Greedy Flow',
      greedy_title:   'ყოველი რუპია. ყოველი დირჰამი.<br>ყველაფერი გათვლილია.',
      greedy_body:    'სიცოცხლე არ ჩერდება სავალუტო ცხრილებისთვის. SetAll-ის Greedy Flow ალგორითმი ხარბად ამცირებს ნებისმიერი ჯგუფის ანაზღაურებისათვის საჭირო ტრანზაქციების რაოდენობას. ერთი გასვლა. ოპტიმალური შედეგი.',
      greedy_cta:     'პორტალის გახსნა',
      how_label:      'როგორ მუშაობს',
      how_title:      'სამი ნაბიჯი ნულოვანი ვალისკენ',
      step1_title:    'შექმენი ჯგუფი',
      step1_body:     'დაარქვი «ბალი-მოგზაურობა», «ბინის გადასახადები» ან სხვა. მოიწვიე წევრები ელ-ფოსტით ან ბმულით — ისინი წამებში შემოდიან.',
      step2_title:    'ჩაწერე ხარჯები მომენტში',
      step2_body:     'დაამატე ხარჯი ნებისმიერი მოწყობილობიდან. აირჩიე ვინ გადაიხადა, ვინ მართება, რომელ ვალუტაში. SetAll გარდაქმნის და ჩაწერს რეალურ დროში.',
      step3_title:    'ანაზღაურე ერთი შეხებით',
      step3_body:     'Greedy Flow-ს ძრავა ყველა ვალს ამცირებს შესაძლო მინიმუმ გადახდებამდე. მოანიშნე ანაზღაურებული — მზადაა.',
      platform_ios:   'iOS და macOS',
      platform_android:'Android',
      platform_windows:'Windows',
      platform_web:   'ვებ-აპლიკაცია',
      cta_label:      'დაიწყე',
      cta_title:      'შექმნილია თანამედროვე სამყაროსთვის.<br>ყველგან ხელმისაწვდომი.',
      cta_body:       'iOS, Android, macOS და Windows-ის ნათელი აპლიკაციები — პლუს სრულფასოვანი ვებ-პორტალი. შენი ჩანაწერი, სადაც კი ხარ.',
      cta_portal:     'პორტალის გახსნა',
      cta_download:   'აპლიკაციის ჩამოტვირთვა',
      footer_privacy: 'კონფიდენციალობის პოლიტიკა',
      footer_terms:   'მომსახურების პირობები',
      footer_help:    'დახმარება და მხარდაჭერა',
      footer_contact: 'კონტაქტი',
    },
    fr: {
      nav_download:   'Télécharger',
      nav_sign_in:    'Connexion',
      beta_text:      "SetAll est en bêta publique — les fonctionnalités peuvent évoluer.",
      beta_feedback:  'Donner un avis →',
      beta_dismiss:   'Fermer',
      hero_eyebrow:   'Bêta publique · Greedy Flow Engine',
      hero_h1:        "Arrêtez de laisser <span class=\"text-gradient\">l'argent</span> freiner votre vie",
      hero_sub:       "Dès que vous payez pour un groupe, SetAll divise, suit et règle — toutes devises, toutes frontières, en temps réel. Plus de relances. Plus de messages gênants. Plus de dettes en attente.",
      hero_cta_portal:'Ouvrir le portail',
      hero_cta_web:   'Application web',
      hero_cta_dl:    "Télécharger l'app",
      hero_scroll:    'Défiler',
      proof_currencies:'Devises',
      proof_sync:     'Synchronisation',
      proof_local:    "Local d'abord",
      proof_platforms:'Plateformes',
      feat_label:     'Pourquoi SetAll',
      feat_title:     'Conçu pour les gens qui <em>bougent</em>',
      feat_body:      "Voyages entre amis, dîners avec des collègues, abonnements partagés — SetAll a été conçu pour chaque enchevêtrement financier que la vie moderne vous impose. Pas de tableur nécessaire.",
      feat1_title:    'Multi-devises, nativement',
      feat1_body:     "Payer en AED, diviser en USD, régler en EUR — les taux de change en direct font les calculs pour que vous ne discutiez plus jamais des conversions.",
      feat2_title:    'Registre en temps réel',
      feat2_body:     "Chaque action se synchronise instantanément sur chaque appareil de votre groupe. Dès qu'une dépense arrive, tout le monde la voit.",
      feat3_title:    'Partages de groupe intelligents',
      feat3_body:     "Égal, pourcentage, détaillé — choisissez comment vous partagez. SetAll mémorise les préférences pour que les groupes récurrents fonctionnent en automatique.",
      feat4_title:    "Centre d'insights",
      feat4_body:     "Un canvas alimenté par IA qui transforme vos données de dépenses en modèles visuels. Comprenez les dépenses avant qu'elles ne deviennent un problème.",
      feat5_title:    'Sécurité dès la conception',
      feat5_body:     "Auth de bout en bout, sécurité au niveau des lignes sur chaque ligne de données. Votre historique financier est le vôtre — pas le nôtre à monétiser.",
      feat6_title:    'Chaque plateforme',
      feat6_body:     "iOS, Android, macOS, Windows, Web — votre registre vous accompagne. Performance native sur chaque OS.",
      greedy_label:   'Le Greedy Flow',
      greedy_title:   'Chaque roupie. Chaque dirham.<br>Tout comptabilisé.',
      greedy_body:    "La vie ne s'arrête pas pour les tableaux de devises. L'algorithme Greedy Flow de SetAll minimise le nombre de transactions pour régler n'importe quel groupe — peu importe la complexité du réseau. Un passage. Résultat optimal.",
      greedy_cta:     'Ouvrir le portail',
      how_label:      'Comment ça fonctionne',
      how_title:      'Trois étapes vers zéro dette',
      step1_title:    'Créer un groupe',
      step1_body:     'Nommez-le "Voyage Bali", "Factures appartement" ou autre. Invitez des membres par email ou lien — ils rejoignent en quelques secondes.',
      step2_title:    "Enregistrer les dépenses au fil de l'eau",
      step2_body:     "Ajoutez une dépense depuis n'importe quel appareil. Choisissez qui a payé, qui doit, dans quelle devise. SetAll convertit et enregistre en temps réel.",
      step3_title:    'Régler en un tap',
      step3_body:     'Le moteur Greedy Flow réduit toutes les dettes au minimum de paiements possibles. Marquez comme réglé, terminé.',
      platform_ios:   'iOS et macOS',
      platform_android:'Android',
      platform_windows:'Windows',
      platform_web:   'Application web',
      cta_label:      'Commencer',
      cta_title:      'Conçu pour le monde moderne.<br>Disponible partout.',
      cta_body:       "Applications natives pour iOS, Android, macOS et Windows — plus un portail web complet. Votre registre, où que vous soyez.",
      cta_portal:     'Ouvrir le portail',
      cta_download:   "Télécharger l'application",
      footer_privacy: 'Politique de confidentialité',
      footer_terms:   "Conditions d'utilisation",
      footer_help:    'Aide et support',
      footer_contact: 'Contact',
    },
    es: {
      nav_download:   'Descargar',
      nav_sign_in:    'Iniciar sesión',
      beta_text:      'SetAll está en beta pública — las funciones pueden cambiar.',
      beta_feedback:  'Enviar comentarios →',
      beta_dismiss:   'Cerrar',
      hero_eyebrow:   'Beta pública · Greedy Flow Engine',
      hero_h1:        'Deja de permitir que el <span class="text-gradient">dinero</span> frene tu vida',
      hero_sub:       'En el momento en que pagas por un grupo, SetAll lo divide, rastrea y liquida — en todas las divisas, en todas las fronteras, en tiempo real. Sin perseguir a nadie. Sin mensajes incómodos. Sin deudas estancadas.',
      hero_cta_portal:'Abrir portal',
      hero_cta_web:   'App web',
      hero_cta_dl:    'Descargar app',
      hero_scroll:    'Desplazar',
      proof_currencies:'Divisas',
      proof_sync:     'Sincronización',
      proof_local:    'Local primero',
      proof_platforms:'Plataformas',
      feat_label:     'Por qué SetAll',
      feat_title:     'Construido para personas que <em>se mueven</em>',
      feat_body:      'Viajes con amigos, cenas con colegas, suscripciones compartidas — SetAll fue diseñado para cada enredo financiero que la vida moderna te lanza. Sin hojas de cálculo.',
      feat1_title:    'Multi-divisa, nativamente',
      feat1_body:     'Paga en AED, divide en USD, liquida en EUR — los tipos de cambio en tiempo real hacen los cálculos para que nunca vuelvas a discutir sobre conversiones.',
      feat2_title:    'Libro mayor en tiempo real',
      feat2_body:     'Cada acción se sincroniza instantáneamente en cada dispositivo de tu grupo. En el momento en que llega un gasto, todos lo ven.',
      feat3_title:    'Divisiones de grupo inteligentes',
      feat3_body:     'Igual, porcentaje, detallado — elige cómo dividir. SetAll recuerda las preferencias para que los grupos repetidos funcionen en piloto automático.',
      feat4_title:    'Centro de insights',
      feat4_body:     'Un canvas impulsado por IA que convierte tus datos de gastos en patrones visuales. Entiende los gastos antes de que se conviertan en un problema.',
      feat5_title:    'Seguro por diseño',
      feat5_body:     'Autenticación de extremo a extremo, seguridad a nivel de fila en cada fila de datos. Tu historial financiero es tuyo — no el nuestro para monetizar.',
      feat6_title:    'Cada plataforma',
      feat6_body:     'iOS, Android, macOS, Windows, Web — tu libro mayor viaja contigo. Rendimiento nativo en cada SO.',
      greedy_label:   'El Greedy Flow',
      greedy_title:   'Cada rupia. Cada dírham.<br>Todo contabilizado.',
      greedy_body:    "La vida no hace pausa para las tablas de divisas. El algoritmo Greedy Flow de SetAll minimiza el número de transacciones necesarias para liquidar cualquier grupo — sin importar lo enredado que esté. Un paso. Resultado óptimo.",
      greedy_cta:     'Abrir portal',
      how_label:      'Cómo funciona',
      how_title:      'Tres pasos hacia cero deudas',
      step1_title:    'Crear un grupo',
      step1_body:     'Nómbralo "Viaje a Bali", "Facturas del piso" o cualquier otra cosa. Invita miembros por email o enlace — están dentro en segundos.',
      step2_title:    'Registrar gastos al momento',
      step2_body:     'Añade un gasto desde cualquier dispositivo. Elige quién pagó, quién debe, en qué divisa. SetAll convierte y registra en tiempo real.',
      step3_title:    'Liquidar con un toque',
      step3_body:     'El motor Greedy Flow colapsa todas las deudas en el mínimo de pagos posibles. Marca como liquidado, listo.',
      platform_ios:   'iOS y macOS',
      platform_android:'Android',
      platform_windows:'Windows',
      platform_web:   'App web',
      cta_label:      'Empezar',
      cta_title:      'Construido para el mundo moderno.<br>Disponible en todas partes.',
      cta_body:       'Apps nativas para iOS, Android, macOS y Windows — más un portal web completo. Tu libro mayor, donde quiera que estés.',
      cta_portal:     'Abrir portal',
      cta_download:   'Descargar la app',
      footer_privacy: 'Política de privacidad',
      footer_terms:   'Términos de servicio',
      footer_help:    'Ayuda y soporte',
      footer_contact: 'Contacto',
    },
  };

  /* ── Language detection ─────────────────────────────────────────────────── */
  function detectLang() {
    try {
      const stored = localStorage.getItem('setall_lang');
      if (stored && LANGS.includes(stored)) return stored;
    } catch (_) {}
    const param = new URLSearchParams(window.location.search).get('lang');
    if (param && LANGS.includes(param)) return param;
    const browser = (navigator.language || navigator.userLanguage || 'en').slice(0, 2).toLowerCase();
    return LANGS.includes(browser) ? browser : 'en';
  }

  function saveLang(lang) {
    try { localStorage.setItem('setall_lang', lang); } catch (_) {}
  }

  /* ── DOM update ─────────────────────────────────────────────────────────── */
  function applyTranslations(lang) {
    const dict = T[lang] || T.en;
    document.documentElement.lang = lang;

    document.querySelectorAll('[data-i18n]').forEach(function (el) {
      const key = el.getAttribute('data-i18n');
      if (dict[key] !== undefined) el.textContent = dict[key];
    });

    document.querySelectorAll('[data-i18n-html]').forEach(function (el) {
      const key = el.getAttribute('data-i18n-html');
      if (dict[key] !== undefined) el.innerHTML = dict[key];
    });

    document.querySelectorAll('[data-i18n-aria]').forEach(function (el) {
      const key = el.getAttribute('data-i18n-aria');
      if (dict[key] !== undefined) el.setAttribute('aria-label', dict[key]);
    });

    // Update active state on language switcher buttons
    document.querySelectorAll('[data-lang-btn]').forEach(function (btn) {
      btn.classList.toggle('lang-active', btn.getAttribute('data-lang-btn') === lang);
    });
  }

  /* ── Language switcher ──────────────────────────────────────────────────── */
  function buildSwitcher() {
    const wrap = document.getElementById('lang-switcher');
    if (!wrap) return;
    LANGS.forEach(function (l) {
      const btn = document.createElement('button');
      btn.setAttribute('data-lang-btn', l);
      btn.setAttribute('title', LANG_NAMES[l]);
      btn.textContent = LANG_LABELS[l];
      btn.addEventListener('click', function () {
        saveLang(l);
        applyTranslations(l);
      });
      wrap.appendChild(btn);
    });
  }

  /* ── Boot ───────────────────────────────────────────────────────────────── */
  function init() {
    buildSwitcher();
    applyTranslations(detectLang());
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  // Expose global helper
  window.setAllLang = function (lang) {
    if (!LANGS.includes(lang)) return;
    saveLang(lang);
    applyTranslations(lang);
  };
})();
