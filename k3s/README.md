# k3s

Single-Node-Kubernetes-Cluster auf der VM `sayit-agent` (Ubuntu 24.04, ARM64, 2 OCPU / 12 GB).

[k3s](https://k3s.io) ist eine zertifiziert konforme, schlanke Kubernetes-Distribution. Sie bringt Container-Runtime, Netzwerk (Flannel), DNS (CoreDNS), Ingress (Traefik), Load Balancer (ServiceLB) und lokalen Speicher bereits mit.

---

## Konfiguration

[`config.yaml`](config.yaml) liegt auf der VM unter `/etc/rancher/k3s/config.yaml` und wird bei der Installation automatisch gelesen.

```yaml
kubelet-arg:
  - "system-reserved=cpu=250m,memory=512Mi"
```

`system-reserved` hält 0,25 CPU und 512 MB RAM für das Betriebssystem frei. Pods können diese Ressourcen nicht belegen – SSH und Systemdienste bleiben auch unter Last erreichbar.

---

## Firewall-Vorbereitung (Oracle-spezifisch)

Die Ubuntu-Images von Oracle bringen eigene `iptables`-Regeln mit, die in den Ketten `INPUT` und `FORWARD` alles außer SSH ablehnen. Ohne Anpassung können Pods nicht miteinander kommunizieren und Traefik erreicht keine Anwendung.

Statt alle Regeln zu entfernen, wird gezielt nur der Cluster-Verkehr erlaubt:

| Netz | Verwendung |
|---|---|
| `10.42.0.0/16` | Pod-Netz |
| `10.43.0.0/16` | Service-Netz |

```bash
# Weiterleitung von und zu Pods erlauben (vor dem REJECT)
sudo iptables -I FORWARD 1 -s 10.42.0.0/16 -j ACCEPT
sudo iptables -I FORWARD 1 -d 10.42.0.0/16 -j ACCEPT

# Pods und Services dürfen den Node selbst erreichen (vor dem REJECT)
sudo iptables -I INPUT 5 -s 10.42.0.0/16 -j ACCEPT
sudo iptables -I INPUT 5 -s 10.43.0.0/16 -j ACCEPT

# Dauerhaft speichern – VOR der k3s-Installation
sudo netfilter-persistent save
```

> **Wichtig:** Die Regeln müssen vor der Installation gespeichert werden. k3s legt bei jedem Start eigene `iptables`-Ketten an. Würden diese mitgespeichert, kollidieren sie beim nächsten Neustart mit den neu erzeugten Regeln.

Von außen bleibt die VM weiterhin geschützt: Eingehender Verkehr, der weder SSH noch Cluster-intern ist, wird abgelehnt. Zusätzlich filtert die OCI Security List auf Netzwerkebene (siehe [`../terraform`](../terraform)).

---

## Installation

```bash
# Konfiguration anlegen
sudo mkdir -p /etc/rancher/k3s
sudo cp config.yaml /etc/rancher/k3s/config.yaml

# k3s installieren
curl -sfL https://get.k3s.io | sh -

# kubectl ohne sudo für den Benutzer ubuntu
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown ubuntu:ubuntu ~/.kube/config
chmod 600 ~/.kube/config
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
source ~/.bashrc
```

`~/.kube/config` enthält Admin-Zugangsdaten zum Cluster und darf nur für den eigenen Benutzer lesbar sein.

---

## Prüfen

```bash
kubectl get nodes
kubectl get pods -A
```

Erwartete System-Pods im Namespace `kube-system`:

| Pod | Aufgabe |
|---|---|
| `coredns` | Internes DNS (`<service>.<namespace>.svc.cluster.local`) |
| `local-path-provisioner` | Persistenter Speicher auf der lokalen Festplatte |
| `metrics-server` | CPU- und RAM-Metriken (`kubectl top`) |
| `traefik` | Ingress Controller für HTTP/HTTPS |
| `svclb-traefik` | Bindet Traefik an die Ports 80/443 der VM |
| `helm-install-traefik*` | Einmalige Installations-Jobs (Status `Completed`) |

Reservierte Ressourcen kontrollieren:

```bash
kubectl describe node sayit-agent | grep -A 6 -E "Capacity|Allocatable"
```

---

## Funktionstest: Ingress → Service → Pod

```bash
kubectl create namespace test
kubectl -n test create deployment web --image=nginx
kubectl -n test expose deployment web --port=80
kubectl -n test create ingress web --rule="test.local/*=web:80"

# Anfrage über Traefik an den Pod
curl -H "Host: test.local" http://localhost   # → "Welcome to nginx!"

# Aufräumen
kubectl delete namespace test
```

Der Test bestätigt den kompletten Weg: Port 80 → ServiceLB → Traefik → Service → Pod – und damit die Firewall-Anpassung.

---

## Nächste Schritte

- Ports 80/443 in der OCI Security List öffnen (Terraform)
- cert-manager für automatische TLS-Zertifikate (Let's Encrypt)
- Zugriff per `kubectl` vom lokalen Rechner über einen SSH-Tunnel
