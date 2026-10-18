# Storingsmelder

Een klein meldingensysteem voor storingen. Je meldt een storing via een
formulier, je ziet de openstaande meldingen in een lijst, en je sluit ze af als
ze opgelost zijn.

Deze applicatie is het startpunt voor **Cloud computing (B-UCLL-MGN13A)**. Je
werkt er het hele semester mee. De applicatie zelf verandert bijna niet, wat
verandert is hoe en waar ze draait.

---

## Wat er in deze repo zit

```
app.py              de applicatie
requirements.txt    de pakketten die ze nodig heeft
templates/          de HTML van de webpagina
```

## Wat er bewust niet in zit

Geen Dockerfile en geen compose-bestand. Die schrijf je zelf, dat is precies
wat je in dit vak leert.

---

## Wat de applicatie nodig heeft

| | |
|---|---|
| Python | 3.11 of hoger |
| Pakketten | staan in `requirements.txt` |
| Poort | 8000, tenzij je `PORT` anders instelt |

## Instellingen

Alles wordt geregeld met environment variables. Er staat niets vast in de code,
en er is geen configuratiebestand dat je moet aanpassen.

| Variabele | Standaard | Wat het doet |
|---|---|---|
| `DATABASE_URL` | leeg | Leeg betekent opslaan in een SQLite-bestand. Vul je hier een PostgreSQL-adres in, dan gebruikt de applicatie die database |
| `SQLITE_PAD` | `/data/storingen.db` | Waar het SQLite-bestand komt te staan |
| `APP_TITEL` | `Storingsmelder` | De titel bovenaan de pagina |
| `PORT` | `8000` | De poort waarop de applicatie luistert |

### Twee standen

De applicatie draait met of zonder aparte database.

**Zonder `DATABASE_URL`** schrijft ze naar een SQLite-bestand. Dat werkt meteen
en je hebt niets anders nodig. Let op waar dat bestand terechtkomt, want daar
kom je later op terug.

**Met `DATABASE_URL`** praat ze met PostgreSQL. Bijvoorbeeld:

```
DATABASE_URL=postgresql://storing:geheim@db:5432/storingen
```

Je hoeft de tabel niet zelf aan te maken. De applicatie doet dat bij het
opstarten als ze nog niet bestaat.

---

## Controleren of ze draait

Naast de gewone pagina is er een adres dat kort antwoordt of alles in orde is:

```
GET /health
```

Draait alles, dan krijg je `{"status": "ok", ...}` met code 200. Kan de
applicatie haar database niet bereiken, dan krijg je code 503. Dat adres komt
later in het semester nog van pas.

---

## Wat je er dit semester mee doet

| Blok | Wat je doet |
|---|---|
| Week 1 tot 4 | Je zet deze applicatie in een container en laat ze samen met een database draaien |
| Week 5 tot 9 | Je zet diezelfde applicatie op een Kubernetes-cluster en maakt ze bereikbaar in je browser |
| Week 10 tot 11 | Je laat een pipeline het image bouwen en klaarzetten |

Je begint dus nooit opnieuw. Elke opdracht bouwt verder op de vorige.

---

## Deze repo is van jou

Je hebt hem gemaakt vanaf het sjabloon, dus dit is jouw kopie. Werk erin, commit
elke les, en push. Indienen doe je met de link naar een commit. Hoe dat precies
gaat, staat in de opdrachtbundel op Toledo.


## Storingsmelder opzetten vanaf nul

Je hebt Docker Desktop nodig, draaiend. Verder niets.

```powershell
git clone https://github.com/MiloCr1/cloud-computing.git
cd cloud-computing
Copy-Item .env.example .env
```

Vul `.env` in. De drie waardes mag je zelf kiezen, bijvoorbeeld:

```
POSTGRES_USER=storing
POSTGRES_PASSWORD=een-wachtwoord-naar-keuze
POSTGRES_DB=storingen
```

Daarna:

```powershell
docker compose up -d --build
```

De applicatie staat op **http://localhost:8000**

Controleren dat alles draait:

```powershell
docker compose ps
```

`db` hoort `(healthy)` te tonen en `web` `Up`. De applicatie bevestigt zelf dat ze met PostgreSQL praat:

```powershell
curl.exe -s http://localhost:8000/health
```

Antwoord: `{"status": "ok", "opslag": "PostgreSQL"}`

Stoppen:

```powershell
docker compose down      # data blijft staan
docker compose down -v   # data wordt ook gewist
```

---

## Het image op ghcr.io

```
ghcr.io/milocr1/storingsmelder:1.0
```

Publiek, dus op te halen zonder in te loggen:

```powershell
docker pull ghcr.io/milocr1/storingsmelder:1.0
```

Versie `1.0`, niet `latest`.

---

## Wat er in de repo zit

```
app.py                de applicatie, ongewijzigd uit het startpakket
requirements.txt      Flask en psycopg
templates/            de HTML
Dockerfile            bouwt het image van de applicatie
.dockerignore         houdt .git en lokale rommel uit de build context
compose.yaml          start web en db samen
.env.example          de namen van de instellingen, met lege waardes
.gitignore            bevat .env, zodat het wachtwoord niet in de repo komt
oefeningen.md         de antwoorden op de oefeningen van de drie labo's
```

`.env` staat bewust niet in de repo om wachtwoorden niet publiek te maken.

---

## Wat ik gedaan heb

### Het image

De Dockerfile vertrekt van `python:3.14-slim`.

`requirements.txt` wordt apart gekopieerd, vóór `pip install`, en pas daarna de rest van de code. Daardoor hangt de pip-laag alleen af van de dependencies en blijft die in de cache bij een codewijziging.

`pip install` krijgt `--no-cache-dir` mee. pip bewaart anders een wheel-cache die na de build nooit meer gebruikt wordt maar wel in de laag zit.

De applicatie draait niet als root maar als `appuser`. Omdat `/data` door root aangemaakt wordt, moet die map eerst aan die gebruiker gegeven worden, anders crasht de applicatie op `unable to open database file` zodra ze haar database wil wegschrijven.

Er zit een `HEALTHCHECK` in die `/health` opvraagt. Omdat er geen curl in het image zit, gebeurt dat met `urllib` uit de standaardbibliotheek.

`.dockerignore` houdt onder meer `.git` buiten de build context. Dat scheelt nu nog weinig, maar die map groeit met elke commit, en zonder die regel zou de volledige git-geschiedenis via `COPY . .` in een laag van een publiek image terechtkomen.

### Applicatie en database samen

`compose.yaml` start twee services. `web` wordt gebouwd uit de Dockerfile, `db`
draait `postgres:18`.

De database publiceert geen poort. De applicatie bereikt haar via het interne
netwerk dat Compose aanmaakt.

De host in `DATABASE_URL` is `db`, de servicenaam. Niet `localhost`, dat is binnen een container de container zelf, en daar luistert niets op 5432.

De data van PostgreSQL staat in het volume `pgdata`, gekoppeld aan `/var/lib/postgresql/18/docker`.

### De opstartvolgorde

Bij een koude start crashte `web` met `Connection refused`. Dat is geen fout in het bestand maar timing: PostgreSQL meldt `ready to accept connections` al terwijl alleen de Unix-socket openstaat, en luistert pas een seconde later op IPv4.

Opgelost met een healthcheck op `db` die `pg_isready -h 127.0.0.1` draait, plus `depends_on: condition: service_healthy` op `web`.

Sindsdien toont `docker compose up` eerst `db Waiting`, dan `db Healthy`, en pas daarna start `web`.

`restart: unless-stopped` staat erbij als vangnet voor onvoorziene crashes.

---

## Dat de data blijft staan

Na `docker compose down` en opnieuw `up -d` staan de meldingen er nog. Na `docker compose down -v` zijn ze weg.