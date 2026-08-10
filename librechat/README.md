# LibreChat Installer (pc-fee)

> **Ein Befehl, komplette LibreChat-Instanz mit Admin-Panel, hinter deinem Nginx Proxy Manager.**

Dieser Installer richtet LibreChat als Docker-Compose-Stack auf einem Debian-12/13-VPS ein. Voraussetzung: du hast bereits den [Nginx Proxy Manager (NPM)](https://pc-fee.com/2026/05/03/nginx-proxy-manager/) installiert.

## Was du bekommst

- **Chat-UI** unter `https://chat.deinedomain.de`
- **Admin-Panel** unter `https://chat-admin.deinedomain.de`
- **pc-fee-Toolkit** direkt im Admin-Panel zum Verwalten deiner KI-Provider-Keys
- **Meilisearch** für Volltextsuche in Chat-Verläufen (optional)
- **MongoDB** für persistente Daten
- Alles erreichbar **ausschließlich über NPM** – kein direkter Container-Zugriff vom Internet

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

## Was danach passiert

Das Skript fragt dich interaktiv nach:

1. **Installationspfad** (Default `/opt/librechat`)
2. **Docker-Netzwerk** für NPM (Default `shared_proxy`)
3. **Chat-Domain** (z. B. `chat.deinedomain.de`)
4. **Admin-Domain** (z. B. `chat-admin.deinedomain.de`)
5. **Admin-E-Mail** (wird dein Login)
6. **Admin-Name** (Anzeigename)
7. **Admin-Passwort** (mind. 12 Zeichen)
8. **JWT-Secret** (leer = wird automatisch erzeugt)
9. **Meilisearch** installieren? (Volltextsuche, Default: ja)

Danach prüft das Skript:
- ✅ Alle Voraussetzungen erfüllt?
- ✅ Keine Konflikte mit bestehenden LibreChat-Containern/Volumes/Netzwerken/Ports? (Schutzregel)
- ✅ NPM-Netzwerk erreichbar?

Bei jedem Konflikt bricht das Skript **ab** mit konkreter Anleitung, statt zu überschreiben.

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
4. Du siehst den Menüpunkt **PC-FEE Toolkit** – dort fügst du deine KI-Provider-Keys hinzu

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
├── librechat.yaml                    # gerendert
└── data/
    ├── mongo/                        # Datenbank
    └── meili/                        # Suchindex (falls installiert)
```

## Häufige Fragen

### Wie update ich LibreChat?

```bash
cd /opt/librechat
sudo docker compose pull api admin-panel
sudo docker compose up -d
```

(Später kommt ein `update.sh` im Installer.)

### Wie füge ich OpenAI/Ollama/Anthropic hinzu?

Im Admin-Panel → **PC-FEE Toolkit** → **Provider** → **Neu** → API-Key eintragen → Speichern. Die `librechat.yaml` wird automatisch aktualisiert.

### Wie deinstalliere ich alles?

```bash
cd /opt/librechat
sudo docker compose down -v   # ACHTUNG: löscht alle Daten!
sudo rm -rf /opt/librechat
```

### Was ist mit RAG / Vektor-Datenbank?

Aktuell nicht im Default-Scope. Du hast auf deinem VPS bereits `pgvector` und `qdrant` laufen – LibreChat kann diese ansprechen, wenn du in `librechat.yaml` unter `ragAPI` oder `memory` die URL `<container-name>:5432` bzw. `:6333` einträgst. Eine geführte Konfiguration im Toolkit ist für eine spätere Version geplant.

### Funktioniert das auf Windows/macOS?

Nur mit WSL2 auf Windows. macOS nativ nicht getestet. Auf Linux-VPS aber problemlos.

## Support

- GitHub Issues: [github.com/nephilim75/scripts/issues](https://github.com/nephilim75/scripts/issues)
- Blog: [pc-fee.com/blog](https://pc-fee.com/blog)
- NPM-Anleitung: [pc-fee.com/2026/05/03/nginx-proxy-manager/](https://pc-fee.com/2026/05/03/nginx-proxy-manager/)
- Docker-Compose-Anleitung: [pc-fee.com/2026/05/03/docker-compose/](https://pc-fee.com/2026/05/03/docker-compose/)
- Offizielle LibreChat-Doku: [librechat.ai/docs](https://www.librechat.ai/docs)

## Lizenz

MIT (oder deine Wahl – Datei `LICENSE` im Repo-Root).

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
                          │       ◄───► pc-fee-toolkit:3000 │
                          └─────────────────────────────────┘
```

**Wichtig:** Kein Service exposed direkt an den Host. Alles geht durch NPM.
