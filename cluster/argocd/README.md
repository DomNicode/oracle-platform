# Argo CD

[Argo CD](https://argo-cd.readthedocs.io) ist der GitOps-Controller der Plattform. Er vergleicht dauerhaft den Stand in Git mit dem Zustand im Cluster und gleicht Abweichungen automatisch aus.

- Weboberfläche: `https://argocd.dompah.de` (Benutzer `admin`)
- Namespace: `argocd`
- Chart: `argo/argo-cd` (geprüft mit Chart 10.x / Argo CD v3.5)

---

## Installation

Argo CD ist die einzige Komponente, die von Hand per Helm installiert wird – alles Weitere installiert Argo CD selbst.

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  -f values.yaml
```

Wichtige Werte in [`values.yaml`](values.yaml):

| Wert | Bedeutung |
|---|---|
| `global.domain` | Domain für Ingress, Zertifikat und Links in der UI |
| `configs.params.server.insecure: true` | TLS endet bei Traefik. Ohne diese Einstellung leitet Argo CD selbst auf HTTPS um → Umleitungsschleife |
| `server.ingress` | Ingress über Traefik, Zertifikat über cert-manager (`letsencrypt-prod`), Secret `argocd-server-tls` |
| `dex.enabled: false` | kein SSO, Login nur mit lokalem Admin |
| `notifications.enabled: false` | keine Benachrichtigungen |

### Erstes Login

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

Nach dem Login unter **User Info → Update Password** ein eigenes Passwort setzen und das Initial-Secret löschen:

```bash
kubectl -n argocd delete secret argocd-initial-admin-secret
```

---

## App of Apps

```
cluster/
├── bootstrap/
│   └── root-app.yaml      ← einmalig: kubectl apply -f root-app.yaml
└── apps/
    └── sayit-agent.yaml   ← von Argo CD automatisch erkannt
```

Die Root-Application `platform-apps` beobachtet `cluster/apps/` in diesem Repo. Jede Datei dort beschreibt eine Anwendung:

- **`source`** – Repo, Branch und Pfad des Helm-Charts
- **`destination`** – Cluster und Namespace
- **`syncPolicy.automated`** – `prune` (aus Git gelöscht → im Cluster gelöscht) und `selfHeal` (manuelle Änderungen werden zurückgesetzt)

**Neue Anwendung hinzufügen:** Application-Datei in `cluster/apps/` anlegen und pushen. Kein `kubectl`, kein `helm`.

---

## Zugriff auf private Projekt-Repos

Für private Repos braucht Argo CD einen **Deploy Key** mit reinem Lesezugriff auf genau dieses Repo.

```powershell
ssh-keygen -t ed25519 -f $HOME\.ssh\argocd-<repo> -C "argocd-<repo>"   # ohne Passphrase
```

1. **GitHub** → Repo → Settings → Deploy keys → Add deploy key → Inhalt der `.pub`-Datei, **ohne** Schreibzugriff
2. **Argo CD** → Settings → Repositories → Connect Repo → *VIA SSH*, URL `git@github.com:DomNicode/<repo>.git`, privaten Key einfügen
3. Privaten Key lokal löschen – er liegt danach nur noch als Secret im Cluster

Aktuell verbunden: `git@github.com:DomNicode/sayit.git`

---

## Secrets außerhalb von Git

Diese Secrets enthalten echte Zugangsdaten und liegen bewusst **nicht** im Repository. Bei einem Neuaufbau müssen sie von Hand neu angelegt werden.

### `ghcr-pull` (Namespace `sayit`)

Lesezugriff auf private Images in GHCR. Basis ist ein GitHub-Token (classic) mit **nur** dem Scope `read:packages`.

```bash
kubectl create namespace sayit
read -s GHCR_TOKEN          # Token einfügen, Enter – wird nicht angezeigt
kubectl -n sayit create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io \
  --docker-username=DomNicode \
  --docker-password="$GHCR_TOKEN"
unset GHCR_TOKEN
```

> Der Token hat ein Ablaufdatum. Danach: neuen Token erzeugen, `kubectl -n sayit delete secret ghcr-pull`, Secret neu anlegen.

### Argo-CD-Repository-Zugang

Wird über die UI angelegt (siehe oben) und als Secret im Namespace `argocd` gespeichert.

**Später geplant:** Sealed Secrets oder External Secrets Operator, damit auch diese Secrets – verschlüsselt – in Git liegen können.

---

## Nützliche Befehle

```bash
kubectl -n argocd get applications            # alle Anwendungen mit Sync- und Health-Status
kubectl -n argocd describe application <name> # Details und Fehlermeldungen
kubectl -n argocd get pods                     # Komponenten von Argo CD
```

Argo CD prüft Git standardmäßig alle 3 Minuten. Sofortige Prüfung: in der UI auf **Refresh** klicken.
