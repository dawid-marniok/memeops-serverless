# Szablon firmowy: funkcja HTTP w Pythonie (MemeOps)

Tak wygląda „repozytorium szablonów” platformy: zespół nie zaczyna od pustego katalogu, tylko od szablonu, który już spełnia zasady firmy.

| Plik | Zasada firmowa, którą spełnia |
|---|---|
| `main.py` | port z `PORT`, logi JSON na stdout, `/healthz`, konfiguracja tylko z env |
| `Dockerfile` | `python:3.12-slim`, użytkownik bez roota (`USER 10001`), brak cache pip |
| `service.yaml` | Knative Service z requests/limits, sondą i bezpiecznym `securityContext` |
| `tests/` | pytest uruchamiany w pipeline przed buildem |

Nowa funkcja: `cp -r templates/python-http app/<nazwa>` i zmiana `handle()`.
`app/meme-gen/` powstał z tego szablonu.

Porównaj z szablonem upstream Knative (`func create -l python`, LAB 3): ASGI, `func.yaml`, budowanie bez Dockerfile. Oba podejścia są poprawne — szablon firmowy daje kontrolę nad obrazem, `func` daje szybki start.
