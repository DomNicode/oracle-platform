# oracle-platform

Infrastructure as Code für meine persönliche DevOps-Plattform auf **Oracle Cloud Infrastructure (OCI)**.
Die Plattform dient als gemeinsame Grundlage für meine Portfolio-Projekte – angefangen mit **SayIt**, einem Sprach-zu-Sprach-KI-Agenten.

Ziel des Projekts ist es, den kompletten Weg von der Infrastruktur bis zur laufenden Anwendung selbst aufzubauen und zu verstehen: Infrastruktur als Code, Container-Orchestrierung, automatisierte Deployments und Monitoring.

---

## Architektur

```mermaid
flowchart TB
    Internet((Internet))

    subgraph OCI["Oracle Cloud – eu-frankfurt-1"]
        subgraph VCN["VCN sayit-vcn · 10.0.0.0/16"]
            IGW[Internet Gateway]
            RT[Route Table<br/>0.0.0.0/0 → IGW]
            SL[Security List<br/>SSH 22, HTTP 80, HTTPS 443, ICMP]

            subgraph Subnet["Public Subnet sayit-net · 10.0.0.0/24"]
                subgraph VM["VM sayit-agent · Ampere A1 · 2 OCPU · 12 GB · Ubuntu 24.04 ARM64"]
                    subgraph K3S["k3s"]
                        TR[Traefik<br/>Ingress]
                        CM[cert-manager<br/>Let's Encrypt]
                        ARGO[Argo CD<br/>GitOps]
                        SS[Sealed Secrets]
                        MON[Prometheus + Grafana<br/>Monitoring]
                        APPS[Anwendungen<br/>z. B. sayit-agent]
                    end
                end
            end
        end
        IP[Reservierte öffentliche IP]
    end

    DNS["Cloudflare DNS<br/>*.dompah.de → reservierte IP"]
    GH["GitHub<br/>Repos + Actions"]
    GHCR[("GHCR<br/>Container-Images")]

    Internet <--> IGW
    DNS -.-> IP
    IGW --- RT
    RT --- Subnet
    SL --- Subnet
    IP --- TR
    TR --> APPS
    CM -. TLS-Zertifikate .-> TR
    GH -- "baut Images" --> GHCR
    ARGO -- "liest Git (Pull)" --> GH
    ARGO -- "synchronisiert" --> APPS
    APPS -. "zieht Images" .-> GHCR
    MON -. "Metriken" .-> APPS
    SS -. "entschlüsselt Secrets" .-> APPS
```

### Verwaltete Ressourcen

| Ressource | Terraform-Name | Beschreibung |
|---|---|---|
| Virtual Cloud Network | `oci_core_vcn.sayit` | Privates Netzwerk, `10.0.0.0/16` |
| Internet Gateway | `oci_core_internet_gateway.sayit` | Verbindung des VCN zum Internet |
| Route Table | `oci_core_route_table.sayit` | Leitet ausgehenden Verkehr über das Internet Gateway |
| Security List | `oci_core_security_list.sayit` | Firewall auf Netzwerkebene (eingehend: SSH, HTTP, HTTPS, ICMP) |
| Subnet | `oci_core_subnet.sayit` | Öffentliches Subnet, `10.0.0.0/24` |
| Compute Instance | `oci_core_instance.sayit_agent` | ARM-VM im Always-Free-Kontingent |
| Reserved Public IP | `oci_core_public_ip.sayit` | Feste öffentliche IP für DNS-Einträge |

Alle Ressourcen liegen im **Always-Free-Kontingent** von OCI (Ampere A1 mit 2 OCPU / 12 GB, 100 GB Boot Volume).

---

## Projektstruktur

```
oracle-platform/
├── terraform/
│   ├── providers.tf                # Provider-Konfiguration (oracle/oci)
│   ├── variables.tf                # Eingabevariablen
│   ├── network.tf                  # VCN, Internet Gateway, Route Table, Security List, Subnet
│   ├── compute.tf                  # VM und reservierte öffentliche IP
│   ├── data.tf                     # Data Sources (Image-Suche, VNIC, private IP)
│   ├── outputs.tf                  # Ausgaben (z. B. öffentliche IP)
│   ├── terraform.tfvars.example    # Vorlage für eigene Werte
│   └── .terraform.lock.hcl         # Fixierte Provider-Version
├── k3s/
│   ├── config.yaml                 # k3s-Konfiguration (/etc/rancher/k3s/config.yaml)
│   ├── traefik-config.yaml         # Traefik: HTTP → HTTPS
│   └── README.md                   # Installation inkl. Firewall-Anpassung
├── cluster/
│   ├── cert-manager/
│   │   ├── cluster-issuers.yaml    # Let's Encrypt (Staging + Prod)
│   │   └── README.md
│   ├── argocd/
│   │   ├── values.yaml             # Helm-Values für Argo CD
│   │   └── README.md               # Installation, Repo-Zugriff, Secrets
│   ├── bootstrap/
│   │   └── root-app.yaml           # Root-Application ("App of Apps") – einmalig angewendet
│   ├── apps/                       # Eine Datei pro Anwendung – von Argo CD automatisch erkannt
│   │   ├── sealed-secrets.yaml
│   │   ├── monitoring.yaml
│   │   └── sayit-agent.yaml
│   ├── sealed-secrets/
│   │   └── README.md               # Secrets verschlüsseln, Schlüssel sichern
│   └── monitoring/
│       ├── grafana-admin.yaml      # Grafana-Admin-Passwort (SealedSecret)
│       └── README.md               # Prometheus, Grafana, eigene Apps überwachen
└── README.md
```

---

## Voraussetzungen

- [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.5 (wegen `import`-Blöcken)
- Ein OCI-Konto mit einem **API-Key** für den eigenen Benutzer
- Eine lokale OCI-Konfiguration unter `~/.oci/config`:

```ini
[DEFAULT]
user=ocid1.user.oc1..<user-ocid>
fingerprint=<fingerprint>
tenancy=ocid1.tenancy.oc1..<tenancy-ocid>
region=eu-frankfurt-1
key_file=~/.oci/oci_api_key.pem
```

Der Provider liest seine Zugangsdaten ausschließlich aus dieser Datei. Es liegen keine Zugangsdaten im Repository.

---

## Nutzung

```bash
cd terraform

# Eigene Werte eintragen
cp terraform.tfvars.example terraform.tfvars

# Provider herunterladen
terraform init

# Änderungen anzeigen (liest den aktuellen Zustand live bei Oracle)
terraform plan

# Änderungen anwenden
terraform apply

# Öffentliche IP anzeigen
terraform output public_ip
```

---

## Entstehung: Import bestehender Infrastruktur

Die VM und das Netzwerk wurden zunächst manuell über die OCI-Konsole angelegt und anschließend **nachträglich in Terraform überführt** – ohne eine einzige Ressource neu zu erstellen.

Vorgehen:

1. `import`-Blöcke für die bestehenden Ressourcen definieren
2. Mit `terraform plan -generate-config-out=generated.tf` Code aus dem Ist-Zustand erzeugen
3. Generierten Code bereinigen:
   - feste OCIDs durch **Referenzen** zwischen Ressourcen ersetzen (z. B. `oci_core_vcn.sayit.id`)
   - Compartment-ID über eine Variable statt fest im Code
   - automatisch gesetzte Felder und Standardwerte entfernen
4. Prüfen, dass der Plan `0 to add, 0 to change, 0 to destroy` meldet
5. `terraform apply` übernimmt die Ressourcen in den State

Der abschließende `terraform plan` meldet *„No changes“* – Code und reale Infrastruktur stimmen überein.

---

## Deployment: CI/CD und GitOps

Anwendungen werden nicht von Hand installiert. Git ist die einzige Wahrheit – Argo CD hält den Cluster dauerhaft auf dem Stand des Repositorys.

```mermaid
sequenceDiagram
    participant Dev as Entwickler
    participant GH as GitHub Actions
    participant GHCR as GHCR
    participant Repo as Projekt-Repo
    participant Argo as Argo CD
    participant K8s as k3s

    Dev->>Repo: git push
    Repo->>GH: Workflow startet
    GH->>GHCR: ARM64-Image bauen und pushen (Tag = Commit-SHA)
    GH->>Repo: Bot-Commit: image.tag in values.yaml
    Argo->>Repo: erkennt Änderung (Polling)
    Argo->>K8s: Helm-Chart rendern und anwenden
    K8s->>GHCR: neues Image ziehen
    K8s->>K8s: Rolling Update (Readiness-Probe)
```

**Aufteilung der Verantwortung:**

| Repo | Inhalt |
|---|---|
| `oracle-platform` | Infrastruktur, Cluster-Komponenten und die Liste der Anwendungen (`cluster/apps/`) |
| Projekt-Repo (z. B. `sayit`) | Code, Dockerfile, Helm-Chart und CI-Workflow der Anwendung |

**App of Apps:** Die Root-Application [`cluster/bootstrap/root-app.yaml`](cluster/bootstrap/root-app.yaml) beobachtet den Ordner `cluster/apps/`. Eine neue Anwendung kommt auf den Cluster, indem dort eine Application-Datei hinzugefügt wird – ohne `kubectl` oder `helm` von Hand.

**Automatische Selbstheilung:** `selfHeal` setzt manuelle Änderungen im Cluster auf den Git-Stand zurück, `prune` entfernt Ressourcen, die aus Git gelöscht wurden.

Details: [`cluster/argocd/README.md`](cluster/argocd/README.md)

### Laufende Anwendungen

| Anwendung | URL | Quelle |
|---|---|---|
| Argo CD | `https://argocd.dompah.de` | [`cluster/argocd`](cluster/argocd) |
| Grafana | `https://grafana.dompah.de` | [`cluster/monitoring`](cluster/monitoring) |
| Sealed Secrets | – (Controller) | [`cluster/sealed-secrets`](cluster/sealed-secrets) |
| SayIt Agent | `https://agent.dompah.de/health` | Repo `sayit`, Ordner `agent/chart` |

---

## Schutzmechanismen

Ampere-A1-Kapazität ist bei OCI knapp. Eine versehentliche Neuerstellung der VM könnte daran scheitern. Deshalb:

- **`prevent_destroy = true`** auf VM und reservierter IP – Terraform bricht ab, statt sie zu löschen oder zu ersetzen.
- **`ignore_changes`** für Felder, deren Änderung bei OCI eine Neuerstellung erzwingen würde (Image, SSH-Key-Metadaten) sowie für von Oracle automatisch gesetzte Tags.
- Das Image wird über eine **Data Source** ermittelt (neuestes Ubuntu 24.04 für A1). Für die laufende VM ist das wirkungslos, bei einem späteren Neuaufbau wird aber automatisch ein aktuelles Image verwendet.

---

## Sicherheit

**Nicht im Repository** (siehe `.gitignore`):

- `terraform.tfstate` – enthält IDs und Details aller Ressourcen
- `terraform.tfvars` – persönliche Werte wie die Tenancy-OCID
- `~/.oci/` – API-Key und Konfiguration liegen ausschließlich lokal

**Secrets in Git – verschlüsselt mit Sealed Secrets:**

- `grafana-admin` – Admin-Zugang für Grafana
- Nur der Controller im Cluster kann sie entschlüsseln; der private Schlüssel ist außerhalb von Git gesichert. Details: [`cluster/sealed-secrets/README.md`](cluster/sealed-secrets/README.md)

**Noch nur im Cluster (Umstellung auf Sealed Secrets geplant):**

- `ghcr-pull` – Lesezugriff auf private Images in GHCR (`read:packages`)
- Argo-CD-Repository-Zugang – read-only Deploy Key für private Projekt-Repos

Wie sie angelegt werden, steht in [`cluster/argocd/README.md`](cluster/argocd/README.md).

**In der Pipeline:**

- Jeder Job erhält nur die Rechte, die er braucht (`packages: write` für den Build, `contents: write` nur für das Tag-Update)
- Der Cluster wird nie von außen angesprochen – Argo CD holt sich Änderungen selbst (Pull statt Push)

**Auf der VM:**

- Login nur per SSH-Key, Passwort-Login deaktiviert
- Automatische Sicherheitsupdates (`unattended-upgrades`)
- Zwei Firewall-Ebenen: OCI Security List (Netzwerk) und `iptables` (Betriebssystem). Ports werden nur geöffnet, wenn ein Dienst sie benötigt.

---

## Roadmap

- [x] VM im Always-Free-Kontingent, Grundabsicherung, reservierte IP
- [x] Infrastruktur als Code mit Terraform (Import der bestehenden Ressourcen)
- [x] Kubernetes mit **k3s**
- [x] Ingress und automatische TLS-Zertifikate (**Traefik**, **cert-manager**, Let's Encrypt)
- [x] CI mit **GitHub Actions** (native ARM64-Builds, private Images in GHCR)
- [x] GitOps mit **Argo CD** (App of Apps, automatisches Tag-Update aus der Pipeline)
- [x] Monitoring mit **Prometheus**, **Grafana** und **Alertmanager** (über Argo CD, persistenter Speicher)
- [x] Secrets verschlüsselt in Git mit **Sealed Secrets**
- [ ] Eigene Metriken der Anwendungen (`/metrics`, ServiceMonitor) und erstes SLO-Dashboard
- [ ] `ghcr-pull` und App-Secrets auf Sealed Secrets umstellen
- [ ] Build-Cache in GitHub Actions, ConfigMap im App-Chart
- [ ] Terraform-State in OCI Object Storage
- [ ] Erstes Projekt auf der Plattform: **SayIt** (Grundgerüst des Agents läuft – als Nächstes LiveKit-Server und KI-Logik)

---

## Lizenz

Privates Lern- und Portfolio-Projekt.
