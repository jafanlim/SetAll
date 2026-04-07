import json, csv

locales = ['en', 'de', 'es', 'fr', 'ka', 'ru']

def flatten(d, prefix=''):
    out = {}
    for k, v in d.items():
        key = (prefix + '.' + k) if prefix else k
        if isinstance(v, dict):
            out.update(flatten(v, key))
        else:
            out[key] = v
    return out

data = {}
for loc in locales:
    fpath = 'assets/translations/' + loc + '.json'
    with open(fpath, encoding='utf-8') as f:
        data[loc] = flatten(json.load(f))

all_keys = set()
for loc in locales:
    all_keys |= set(data[loc].keys())

with open('docs/i18n/translation_audit.csv', 'w', newline='', encoding='utf-8') as f:
    w = csv.writer(f)
    w.writerow(['key'] + locales)
    for key in sorted(all_keys):
        w.writerow([key] + [data[loc].get(key, '') for loc in locales])

missing = []
en_keys = sorted(data['en'].keys())
for key in en_keys:
    for loc in locales[1:]:
        if key not in data[loc]:
            missing.append([key, loc])

with open('docs/i18n/missing_translations.csv', 'w', newline='', encoding='utf-8') as f:
    w = csv.writer(f)
    w.writerow(['key', 'missing_locale'])
    w.writerows(missing)

print('audit: ' + str(len(all_keys)) + ' keys, missing: ' + str(len(missing)))
