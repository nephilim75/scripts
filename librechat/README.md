# LibreChat Installer (pc-fee)

> **Ein Befehl, komplette LibreChat-Instanz mit Admin-Panel, hinter deinem Nginx Proxy Manager.**

Dieser Installer richtet LibreChat als Docker-Compose-Stack auf einem Debian-12/13-VPS ein. Voraussetzung: du hast bereits den [Nginx Proxy Manager (NPM)](https://pc-fee.com/2026/05/03/nginx-proxy-manager/) installiert.

## Was du bekommst

- **Chat-UI** unter `https://chat.deinedomain.de`
- **Admin-Panel** unter `https://chat-admin.deinedomain.de`
- **Meilisearch** für Volltextsuche in Chat-Verläufen (optional)
- **MongoDB** für persistente Daten
- Alles erreichbar **ausschließlich über NPM** – kein direkter Container-Zugriff vom Internet

> **Hinweis zu API-Keys:** In dieser Version werden API-Keys für KI-Provider direkt in `librechat.yaml` hinterlegt (per Editor). Eine komfortablere Verwaltung im Admin-Panel ist für eine spätere Version geplant.

## Voraussetzungen

| | Anforderung | Anleitung |
|---|---|---|
| **VPS** | Debian 12 oder 13, ≥ 2 GB RAM, ≥ 10 GB frei | beliebiger Hoster |
| **NPM** | läuft bereits, Netzwerk `shared_proxy` | [pc-fee.com/2026/05/03/nginx-proxy-manager/](https://pc-fee.com/2026/05/03/nginx-proxy-manager/) |
| **Docker** | Version ≥ 20.10 mit Compose-Plugin v2 | [pc-fee.com/2026/05/03/docker-compose/](https://pc-fee.com/2026/05/03/docker-compose/) |
| **Domain** | A-Record zeigt auf deine VPS-IP | beim Domain-Provider |
| **SSH** | Zugriff mit `sudo` | – |

## Installation

### Schnellinstallation (Einzeiler)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/install.sh)
```

> ⚠️ Das Skript läuft mit Root-Rechten, weil Docker-Operationen und Verzeichnisse unter `/opt/librechat` diese benötigen. Du vertraust damit dem Code auf [GitHub](https://github.com/nephilim75/scripts/tree/main/librechat). Empfehlung: vor dem ersten Lauf einmal durchlesen.

### Manuell mit Review

```bash
git clone https://github.com/nephilim75/scripts.git /tmp/pcfee-scripts
cd /tmp/pcfee-scripts/librechat
less install.sh   # vorher durchschauen
sudo ./install.sh
```

## Was das Skript tut

| Schritt | Was passiert |
|---|---|
| **0** | Voraussetzungen prüfen (OS, Docker, NPM, RAM, Disk, envsubst) |
| **0.5** | Konflikte prüfen – bricht ab, wenn bereits Container/Volumes/Netzwerke/Ports belegt sind (Schutzregel: niemals überschreiben) |
| **1** | Installationspfad, Netzwerk, Domains, Admin-Daten, JWT-Secret, Meilisearch j/n abfragen |
| **2** | Templates rendern via `envsubst` → `docker-compose.yml`, `librechat.yaml`, `.env` |
| **3** | Ersten Admin-User in MongoDB anlegen (bcrypt via Node im librechat-api-Image, Insert via mongosh) |
| **4** | Container starten, auf Health-Checks warten, NPM-Hinweise ausgeben |

## NPM-Proxy-Hosts einrichten

Nach der Installation gibt dir das Skript zwei Hinweis-Blöcke für NPM. Lege sie manuell in NPM an:

### Host 1: Chat-Domain

| Feld | Wert |
|---|---|
| Domain | `chat.deinedomain.de` |
| Scheme | `http` |
| Forward Hostname/IP | `api` |
| Forward Port | `3080` |
| Websockets Support | ✅ |
| SSL | Let's Encrypt |

### Host 2: Admin-Panel-Domain

| Feld | Wert |
|---|---|
| Domain | `chat-admin.deinedomain.de` |
| Scheme | `http` |
| Forward Hostname/IP | `admin-panel` |
| Forward Port | `3000` |
| Websockets Support | ✅ |
| SSL | Let's Encrypt |

## Erster Login

1. Browser → `https://chat.deinedomain.de`
2. Login mit deiner Admin-E-Mail + Passwort
3. Klick oben rechts auf **Admin Panel**

## API-Keys für KI-Provider hinterlegen

In dieser Version (Scope 1.0) ohne Toolkit. Zwei Wege:

### Weg 1: Über das LibreChat-Admin-Panel

Falls deine LibreChat-Version das schon unterstützt:
- Admin-Panel → **Endpoints** → Provider hinzufügen → API-Key eintragen

### Weg 2: Manuell in `librechat.yaml` (empfohlen)

```bash
sudo nano /opt/librechat/librechat.yaml
```

Trage unter `endpoints:` ein:

```yaml
endpoints:
  openAI:
    apiKey: "sk-..."
    models: ["gpt-4o", "gpt-4o-mini"]
    title: "OpenAI"
  anthropic:
    apiKey: "sk-ant-..."
    models: ["claude-3-5-sonnet-latest"]
    title: "Anthropic"
```

Speichern, dann API neu starten:

```bash
cd /opt/librechat
sudo docker compose restart api
```

> Die Datei hat `chmod 644`, du brauchst `sudo` zum Editieren.

## Wie update ich LibreChat?

```bash
cd /opt/librechat
sudo docker compose pull api admin-panel
sudo docker compose up -d
```

(Später kommt ein `update.sh` im Installer.)

## Was passiert, wenn ich das Skript erneut laufen lasse?

Das Skript erkennt eine bestehende Installation über `.librechat-install.conf` und fragt nach:
- **Reconfigure** – nur Konfig ändern (z. B. Domain updaten)
- **Reinstall** – Container neu starten, Daten bleiben
- **Abbrechen**

**Es werden niemals Daten gelöscht ohne explizite Bestätigung.**

## Wo liegen meine Daten?

```
/opt/librechat/
├── .env                              # Zugangsdaten — chmod 600
├── .librechat-install.conf           # Konfiguration — chmod 600
├── docker-compose.yml                # gerendert
└── librechat.yaml                    # gerendert
```

## Wie deinstalliere ich alles?

```bash
cd /opt/librechat
sudo docker compose down -v   # ACHTUNG: löscht alle Daten!
sudo rm -rf /opt/librechat
```

## Häufige Fragen

### Funktioniert das auf Windows/macOS?

Nur mit WSL2 auf Windows. macOS nativ nicht getestet.

### Was ist mit RAG / Vektor-Datenbank?

Aktuell nicht im Default-Scope. Du kannst später `librechat.yaml` erweitern und in `docker-compose.yml` zusätzliche Services eintragen (Anleitung in der offiziellen LibreChat-Doku).

### Das Skript bricht mit "Konflikte gefunden" ab?

Das ist Absicht (Schutzregel). Löse den Konflikt mit dem ausgegebenen Befehl, dann Skript erneut laufen lassen. Bestehende Daten werden **nie** überschrieben.

### Ich habe mein Admin-Passwort vergessen?

```bash
cd /opt/librechat
sudo docker compose exec mongodb mongosh librechat --eval '
  db.users.updateOne(
    {email: "deine@email.de"},
    {$$set: {password: "\$2b\$12$$..."}}
  )
'
```

(Zur Hash-Erzeugung denselben Node-Befehl wie der Installer verwenden — Details in einer späteren Anleitung.)

## Support

- GitHub Issues: [github.com/nephilim75/scripts/issues](https://github.com/nephilim75/scripts/issues)
- Blog: [pc-fee.com/blog](https://pc-fee.com/blog)
- NPM-Anleitung: [pc-fee.com/2026/05/03/nginx-proxy-manager/](https://pc-fee.com/2026/05/03/nginx-proxy-manager/)
- Docker-Compose-Anleitung: [pc-fee.com/2026/05/03/docker-compose/](https://pc-fee.com/2026/05/03/docker-compose/)
- Offizielle LibreChat-Doku: [librechat.ai/docs](https://www.librechat.ai/docs)

## Lizenz

MIT.

## Architektur-Übersicht

```
Browser
  │
  ├── https://chat.deinedomain.de ─────► NPM ──► api:3080
  │
  └── https://chat-admin.deinedomain.de ► NPM ──► admin-panel:3000
                                                │
                                                ▼
                          ┌─────────────────────────────────┐
                          │  Docker-Netzwerk: shared_proxy  │
                          │  (extern, vom NPM-Stack)        │
                          └─────────────────────────────────┘
                                                │
                          ┌─────────────────────────────────┐
                          │  Docker-Netzwerk: librechat_internal
                          │  (intern, vom Installer erstellt)│
                          │                                  │
                          │  api ◄───► mongodb:27017        │
                          │       ◄───► meilisearch:7700     │
                          └─────────────────────────────────┘
```

**Wichtig:** Kein Service exposed direkt an den Host. Alles geht durch NPM.
