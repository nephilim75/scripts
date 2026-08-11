<!-- TODO: Header-Screenshot hier einfuegen, wenn vorhanden -->

# LibreChat Installer – powered by pc-fee.com

[![Blog](https://img.shields.io/badge/blog-pc--fee.com-blue)](https://pc-fee.com/blog)
[![GitHub](https://img.shields.io/badge/github-nephilim75%2Fscripts-black)](https://github.com/nephilim75/scripts/tree/main/librechat)

Ein einzeiliges Installations-Script für **LibreChat** hinter einem bestehenden **Nginx Proxy Manager** auf Debian 12/13. Inklusive MongoDB, Meilisearch und automatisch angelegtem Admin-User.

> Zielgruppe: VPS-Betreiber mit Grundkenntnissen in Docker & DNS. Kein Tooling, kein Python, kein manuelles `docker compose` getippe.

## Schnellstart

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/install.sh)
```

Das war's. Das Script fragt Dich interaktiv nach den nötigen Eingaben (siehe [Konfiguration](#konfiguration)) und macht danach alles von selbst.

### Manuell (statt curl|bash)

```bash
git clone https://github.com/nephilim75/scripts.git
cd scripts/librechat
sudo bash install.sh
```

## Voraussetzungen

Bevor Du das Script startest, muss Folgendes bereits laufen:

- **Docker + Docker Compose Plugin v2** sind installiert ([Anleitung](https://pc-fee.com/blog))
- **Nginx Proxy Manager (NPM)** läuft ([Anleitung](https://pc-fee.com/blog))
- Das Docker-Netzwerk **`shared_proxy`** existiert (legt der NPM-Installer an)
- Zwei Domains zeigen per A/AAAA-Record auf Deinen VPS:
  - Eine für den Chat (z.B. `chat.deinedomain.de`)
  - Eine für das Admin-Panel (z.B. `chat-admin.deinedomain.de`)

## Was wird installiert

Vier Docker-Container in zwei Docker-Netzwerken:

| Service | Image | Interner Port | Netzwerk(e) |
|---|---|---|---|
| `librechat-mongo` | `mongo:8.0.20` | 27017 | `librechat_internal` |
| `librechat-meili` | `getmeili/meilisearch:v1.35.1` | 7700 | `librechat_internal` |
| `librechat-api` | `registry.librechat.ai/danny-avila/librechat:dev-latest` | 3080 | `shared_proxy` + `librechat_internal` |
| `librechat-admin` | `registry.librechat.ai/clickhouse/librechat-admin-panel:latest` | 3000 | `shared_proxy` |

**Wichtig:** Es gibt **keine** Host-Port-Bindings (`ports:`) auf api oder admin-panel. Beide sind nur über NPM und damit über Deine Domains erreichbar. Wer die Server-IP kennt, kommt nicht direkt dran.

### Netzwerk-Topologie

```
                              ┌──────────────────────────┐
   Internet ── HTTPS ────────►│   Nginx Proxy Manager    │
                              │   (shared_proxy)         │
                              └────────┬─────────────────┘
                                       │
              ┌────────────────────────┼────────────────────────┐
              │                        │                        │
              ▼                        ▼                        ▼
       librechat-api           librechat-admin           (andere NPM-Services)
       (Port 3080)             (Port 3000)
              │                        │
              ▼                        ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │   librechat_internal (intern, vom Stack angelegt)                │
   │                                                                  │
   │   ┌────────────────┐                ┌────────────────────┐       │
   │   │ librechat-mongo│◄──────────────►│  librechat-meili   │       │
   │   │ (Port 27017)   │                │  (Port 7700)       │       │
   │   └────────────────┘                └────────────────────┘       │
   └──────────────────────────────────────────────────────────────────┘
```

## Konfiguration

Das Script fragt Dich folgende Werte ab (Defaults in eckigen Klammern):

| Frage | Default | Hinweis |
|---|---|---|
| Installationspfad | `/opt/librechat` | Absoluter Pfad, änderbar (z.B. `/srv/chat`) |
| Docker-Netzwerk | `shared_proxy` | Muss vom NPM-Installer existieren |
| Chat-Domain | — | Pflicht, z.B. `chat.deinedomain.de` |
| Admin-Panel-Domain | — | Pflicht, muss ungleich der Chat-Domain sein |
| Admin-E-Mail | — | Wird zum Login verwendet |
| Admin-Username | aus E-Mail-Präfix | Default z.B. `admin` aus `admin@example.com` |
| Admin-Anzeigename | = Username | Frei wählbar |
| Admin-Passwort | — | Mind. 12 Zeichen, wird 2× abgefragt |
| JWT-Secret | leer = generieren | Eigene Eingabe möglich, mind. 32 Zeichen empfohlen |

Vor dem eigentlichen Start zeigt das Script eine **Zusammenfassung** zur Bestätigung. Erst nach Deinem `j` geht es los.

## Was das Script macht

Das Script läuft in fünf Schritten:

1. **Schritt 0 – Voraussetzungen + Konflikt-Erkennung**
   Prüft Docker, Compose, NPM, das Docker-Netzwerk und ob bereits LibreChat-Container/Images/Volumes existieren. Bricht sauber ab, wenn etwas nicht stimmt — bestehende Installationen werden **nie** überschrieben.

2. **Schritt 1 – Interaktive Konfiguration**
   Fragt alle Werte ab (siehe oben), validiert Domain- und E-Mail-Format.

3. **Schritt 2 – Konfiguration schreiben**
   Generiert die fehlenden Secrets (`JWT_SECRET`, `CREDS_KEY`, `CREDS_IV`, `MEILI_MASTER_KEY`), legt Datenverzeichnisse an und schreibt `.env`, `docker-compose.yml` und `librechat.yaml` in den Installationspfad.

4. **Schritt 3 – Stack starten + Admin-Seed**
   Startet MongoDB und Meilisearch, wartet auf deren Healthcheck, startet dann api und admin-panel. Anschließend wird der Admin-User via `npm run create-user` direkt in der MongoDB angelegt.

5. **Schritt 4 – Status + nächste Schritte**
   Zeigt den `docker compose ps`-Output und gibt Dir eine Anleitung, wie Du die zwei NPM-Proxy-Hosts einrichtest.

## Nach der Installation

### 1. NPM-Proxy-Hosts einrichten

Lege in Deinem Nginx Proxy Manager **zwei** Proxy Hosts an:

**Host 1 – Chat:**
- Domain: `chat.deinedomain.de`
- Scheme: `http`
- Forward Hostname: `librechat-api`
- Forward Port: `3080`
- Websockets: **aktiviert**
- SSL: **Request a new Certificate (Let's Encrypt)**, Force SSL an, HTTP/2 an, HSTS an

**Host 2 – Admin-Panel:**
- Domain: `chat-admin.deinedomain.de`
- Scheme: `http`
- Forward Hostname: `librechat-admin`
- Forward Port: `3000`
- Websockets: **aktiviert**
- SSL: **Request a new Certificate (Let's Encrypt)**, Force SSL an, HTTP/2 an, HSTS an

### 2. Erster Login

```
Browser → https://chat.deinedomain.de
Login mit der Admin-E-Mail und dem Passwort aus der Installation
```

### 3. LLM-Provider einrichten

Ohne Provider-Endpoint kann LibreChat nichts antworten. Trage sie in `librechat.yaml` ein:

```bash
sudo nano /opt/librechat/librechat.yaml
# Beispiel-Block ergänzen:
#
# endpoints:
#   openAI:
#     apiKey: "sk-..."
#     models: ["gpt-4o", "gpt-4o-mini"]
#   anthropic:
#     apiKey: "sk-ant-..."
#     models: ["claude-3-5-sonnet-20241022"]
#   google:
#     apiKey: "..."
#     models: ["gemini-1.5-pro"]

sudo cd /opt/librechat && sudo docker compose restart api
```

Welche Provider-Keys Du wo bekommst, steht in der [LibreChat-Dokumentation](https://www.librechat.ai/docs/configuration/librechat_yaml).

## Befehle zur Wiederholung

```bash
# In den Installationsordner wechseln
cd /opt/librechat

# Status ansehen
sudo docker compose ps

# Logs ansehen
sudo docker compose logs -f
sudo docker compose logs -f api

# Stack neustarten
sudo docker compose restart

# Nur api neustarten (nach librechat.yaml-Änderungen)
sudo docker compose restart api

# Auf neue Image-Versionen prüfen
sudo docker compose pull

# Stack stoppen
sudo docker compose down

# Admin-User nachträglich anlegen (z.B. weitere Admins)
sudo docker compose exec api sh -c 'cd /app/config && npm run create-user'
```

## Update / Upgrade

> **Hinweis:** Update-Mechanik ist aktuell **nicht** im Scope dieses Scripts. Empfohlene Vorgehensweise bei neuen Versionen:

```bash
cd /opt/librechat
sudo docker compose pull          # neue Images laden
sudo docker compose up -d         # Stack neu starten
sudo docker system prune -f       # alte Images aufräumen
```

Vor jedem Update: **Snapshot/Backup der MongoDB-Daten nicht vergessen.**

## Datensicherung

> **Hinweis:** Backup-Mechanik ist aktuell **nicht** im Scope dieses Scripts.

Manuelles Backup der Daten:

```bash
# MongoDB
sudo docker exec librechat-mongo mongosh librechat --eval 'db.adminCommand({fsync:1})'
sudo tar czf mongo-backup-$(date +%F).tar.gz -C /opt/librechat/data/mongo .

# Meilisearch
sudo tar czf meili-backup-$(date +%F).tar.gz -C /opt/librechat/data/meili .
```

## Troubleshooting

### Script bricht ab mit "Nginx Proxy Manager läuft nicht"

NPM muss vor LibreChat installiert sein und laufen. Siehe [Voraussetzungen](#voraussetzungen).

### Script bricht ab mit "Netzwerk shared_proxy fehlt"

Das Netzwerk wird vom NPM-Installer angelegt. Entweder:

- Du hast einen anderen Netzwerknamen verwendet → gib diesen beim Prompt an
- Das Netzwerk existiert wirklich nicht → Script bietet an, es anzulegen. **Danach NPM neu starten**, damit es sich in das Netzwerk einklinkt.

### Script bricht ab bei Konflikt mit bestehenden Containern

Das ist Absicht. Die Schutzregel verhindert, dass eine bestehende LibreChat-Installation überschrieben wird. Lösung:

```bash
# Container stoppen und entfernen
sudo docker rm -f librechat-api librechat-admin librechat-mongo librechat-meili

# Volumes entfernen (ACHTUNG: löscht alle Daten!)
sudo docker volume rm librechat_mongo librechat_meili
```

### api wird nicht healthy

```bash
cd /opt/librechat
sudo docker compose logs api
```

Häufigste Ursachen:
- Falsche `JWT_SECRET` (muss mind. 32 Zeichen lang sein)
- MongoDB noch nicht bereit (Script wartet 60s, manchmal reicht das nicht)
- Falsche `librechat.yaml`-Syntax

### Admin-Seed fehlgeschlagen

Das Script legt den Admin-User via `npm run create-user` an. Falls das fehlschlägt:

```bash
cd /opt/librechat
sudo docker compose exec api sh -c 'cd /app/config && npm run create-user'
```

Wenn die Fehlermeldung `MODULE_NOT_FOUND` lautet: das ist ein bekannter Bug im LibreChat-Image. Der Workaround `cd /app/config` ist im Script bereits eingebaut — wenn er trotzdem auftritt, bitte Issue auf GitHub melden.

### Admin-Panel nicht erreichbar

Das Admin-Panel hat **keinen** öffentlichen Port. Es ist **nur** über NPM erreichbar. Prüfe:

- NPM-Proxy-Host existiert mit korrekter Domain
- NPM-Container ist im `shared_proxy`-Netzwerk
- SSL-Zertifikat wurde von Let's Encrypt ausgestellt (nicht selbstsigniert)

## Was bewusst nicht enthalten ist

Diese Spec-Version (`v1.5`) deckt bewusst nur den Standard-Installationsweg ab:

- ❌ **Passwort-Reset / SMTP / Mailgun** — kommt in einer späteren Version über eine CLI. Bis dahin ist `ALLOW_PASSWORD_RESET=false` hart gesetzt.
- ❌ **Backup / Restore** — siehe manuelles Vorgehen oben
- ❌ **Auto-Update-Mechanik** — manuelle `docker compose pull` wie oben beschrieben
- ❌ **Multi-Tenant / mehrere Admins** — aktuell nur ein Admin-User per Installer; weitere über den `create-user`-Befehl
- ❌ **Plugin-Entwicklung, Logging/Monitoring** — out of scope

## AI Transparency

Dieses Install-Script wurde mit Unterstützung von KI erstellt ([Nils Weber, KI-Assistent bei pc-fee.com](https://pc-fee.com)) und vor Veröffentlichung geprüft. Nutzung auf eigene Gefahr. Backups sind Pflicht.

## Mehr Infos

- 📖 Blog-Artikel: <https://pc-fee.com/blog>
- 💻 GitHub: <https://github.com/nephilim75/scripts/tree/main/librechat>
- 📚 LibreChat-Doku: <https://www.librechat.ai/docs>
- 🔧 Nginx Proxy Manager: <https://nginxproxymanager.com/>
