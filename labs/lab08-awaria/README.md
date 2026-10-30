# lab08 — Awaria w piątek 16:55

| Dzień | Czas | Po bloku |
|---|---|---|
| 2 | 40 min | 2.4 Monitoring, logi i troubleshooting |

> **Zgłoszenie od PO:** „Piątek, 16:55. Zespół wypchnął trzy zmiany przed weekendem. Telefony od organizatora się urywają.”

**Cel:** diagnozujesz trzy typowe awarie funkcji na Knative — od objawu do przyczyny — i naprawiasz każdą jedną zmianą.

**Zasada:** najpierw dowód, potem zmiana. Każdą hipotezę potwierdzasz komendą i wpisujesz do dziennika.

## Przed startem

```bash
tools/dogon.sh lab08            # tylko jeśli LAB 7 nie skończony
labs/lab08-awaria/sprawdz.sh    # → SUKCES: 4/4 (zdrowy stan przed awariami)
```

Przydatne komendy:

```bash
kn service describe meme-gen -n memeops
kn revision list -n memeops -s meme-gen
kubectl get pods -n memeops -l serving.knative.dev/service=meme-gen
kubectl describe pod -n memeops <pod>
kubectl get events -n memeops --sort-by=.lastTimestamp | tail -20
stern -n memeops meme-gen -c user-container
```

Z `--monitoring`: dashboard **MemeOps — funkcja Knative** (kody odpowiedzi, restarty i OOMKilled).

## Zgłoszenia

Wdrażasz zgłoszenie, diagnozujesz, naprawiasz, sprawdzasz — dopiero potem następne.

```bash
labs/lab08-awaria/awaria.sh 1    # potem diagnoza, naprawa, labs/lab08-awaria/sprawdz.sh
```

| # | Co mówi zespół | Co zgłasza organizator |
|---|---|---|
| 1 | „Wdrożyliśmy 2.3.0 z nowym szablonem.” | „Nowego szablonu nie ma. Czy wdrożenie w ogóle poszło?” |
| 2 | „Obniżyliśmy limity pamięci, będzie taniej.” | „Małe memy działają, ale memy HD (`scale` 8) kończą się błędem 502.” |
| 3 | „Zrotowaliśmy klucz JWT do nowego Secretu.” | „Po rotacji nowa wersja nie wstaje, a stare tokeny nadal działają. Czy rotacja się udała?” |

Mem HD z tokenem do odtworzenia objawu:

```bash
export JWT_SECRET=$(kubectl -n memeops get secret meme-jwt -o jsonpath='{.data.JWT_SECRET}' | base64 -d)
curl -s -XPOST http://meme-gen.memeops.127.0.0.1.sslip.io/api/memes \
  -H "Authorization: Bearer $(tools/token.py test 10)" -d '{"top":"HD","scale":8}' -w ' → %{http_code}\n'
```

Naprawiasz, jak chcesz: `kn service update …`, `kubectl edit ksvc meme-gen -n memeops` albo poprawiony manifest. Po każdej naprawie: `labs/lab08-awaria/sprawdz.sh`.

## Dziennik

Skopiuj do `labs/lab08-awaria/dziennik.md`:

| # | Objaw | Hipoteza | Komenda weryfikująca | Wynik | Przyczyna | Poprawka |
|---|---|---|---|---|---|---|
| 1 | | | | | | |
| 2 | | | | | | |
| 3 | | | | | | |

## SUKCES

- [ ] po każdym zgłoszeniu `sprawdz.sh` → `SUKCES: 4/4`
- [ ] w dzienniku każda poprawka ma potwierdzoną przyczynę (komenda + wynik)
- [ ] umiesz wyjaśnić, dlaczego przy zgłoszeniach 1 i 3 użytkownicy nadal dostawali memy

## Dla chętnych

- Zgłoszenie 4 (wymyśl sam): zepsuj coś koledze/koleżance z grupy jednym poleceniem `kn service update` i daj im objaw, nie przyczynę.
- Ile trwa, zanim rewizja ze zgłoszenia 1 dostanie status `False` zamiast `Unknown`? Który parametr o tym decyduje? (`progress-deadline` w `config-deployment`)

## Gdy coś nie działa

| Objaw | Co zrobić |
|---|---|
| `kubectl apply`: `Saw the following changes without a name change` | zmień albo usuń `spec.template.metadata.name` (pułapka z LAB 7) |
| `sprawdz.sh` czeka długo | pod po OOMKilled się restartuje — poczekaj 20 s i powtórz |
