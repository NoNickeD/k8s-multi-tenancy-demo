# Kubernetes Multi-Tenancy Demo: Capsule vs vCluster

Hands-on demo comparing **Capsule** (soft isolation) and **vCluster** (hard isolation) on Azure Kubernetes Service with full GitOps deployment.

**Blog Post:** [Building a Multi-Tenancy Platform with Capsule and vCluster - Hard vs Soft Isolation](https://srekubecraft.io/posts/k8s-multi-tenancy/)

## Architecture

- **AKS Cluster:** 1.33.3 with 3 specialized node pools
- **GitOps:** ArgoCD deployed via OpenTofu, manages all platform components
- **Platform Components:** Capsule, Prometheus, Grafana, cert-manager, External Secrets Operator
- **Capsule Tenants:** 3 internal teams (platform-team, data-team, ml-team)
- **vCluster Tenants:** 3 customer environments (customer-a, customer-b, customer-c)

## Prerequisites

```bash
# Required tools
az login
kubectl version
helm version
task --version

# Optional
vcluster --version  # For vCluster management
```

## Repository Structure

```
.
├── argocd/
│   └── apps/              # ArgoCD Applications (Capsule, Prometheus, cert-manager, etc.)
├── capsule/
│   ├── tenants/           # Tenant CRD definitions
│   ├── namespaces/        # Pre-configured namespaces
│   └── service-accounts/  # Tenant service accounts
├── vcluster/
│   ├── customer-a-values.yaml
│   ├── customer-b-values.yaml
│   └── customer-c-values.yaml
├── tofu/
│   ├── environments/demo/ # OpenTofu configuration
│   └── modules/           # AKS, networking, identity, ArgoCD modules
└── Taskfile.yml           # Task automation
```

## Deployment Flow

```
OpenTofu → AKS + ArgoCD → ArgoCD Apps → Capsule/Prometheus/etc → Tenants → vClusters
```

## Quick Start

### 1. Configure Variables

Create `tofu/environments/demo/terraform.tfvars`:

```hcl
environment            = "demo"
location               = "westeurope"
kubernetes_version     = "1.33.3"
owner_email            = "your-email@example.com"
aks_admin_user_emails  = ["admin@example.com"]
```

### 2. Deploy Infrastructure

```bash
# Deploy AKS cluster with ArgoCD
task infra-apply

# Verify deployment
task verify-cluster
task verify-nodepools
task status
```

**What gets deployed:**

- AKS cluster with 3 node pools:
  - `system`: 2-5 nodes (Standard_D2s_v3) - Platform services
  - `capsule`: 2-10 nodes (Standard_D4s_v3) - Capsule workloads
  - `vcluster-control-plane`: 2-8 nodes (Standard_D4s_v3) - vCluster control planes
- Azure Container Registry
- Azure Key Vault with workload identity
- ArgoCD (installed via Terraform)

### 3. Deploy Platform Components via ArgoCD

```bash
# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Access ArgoCD UI (optional)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Deploy all platform applications
kubectl apply -f argocd/apps/

# Wait for applications to sync
kubectl get applications -n argocd -w
```

**Applications deployed via ArgoCD:**

- `prometheus-crds`: Prometheus Operator CRDs
- `prometheus`: Prometheus + Grafana + Alertmanager stack
- `cert-manager`: Certificate management
- `external-secrets`: External Secrets Operator with Azure Key Vault
- `capsule`: Multi-tenancy operator

### 4. Verify Platform Components

```bash
# Check ArgoCD applications
kubectl get applications -n argocd

# Verify Capsule
kubectl get pods -n capsule-system
kubectl get crd tenants.capsule.clastix.io

# Verify Prometheus stack
kubectl get pods -n monitoring

# Verify cert-manager
kubectl get pods -n cert-manager

# Verify external-secrets
kubectl get pods -n external-secrets
```

### 5. Deploy Capsule Tenants

```bash
# Create tenants
kubectl apply -f capsule/tenants/

# Verify tenants
kubectl get tenants

# Create namespaces for tenants
kubectl apply -f capsule/namespaces/

# Deploy service accounts
kubectl apply -f capsule/service-accounts/
```

**Tenant Configuration:**

| Tenant        | Namespaces | CPU Limit | Memory Limit | Special Resources |
| ------------- | ---------- | --------- | ------------ | ----------------- |
| platform-team | 5          | 40        | 80Gi         | -                 |
| data-team     | 5          | 40        | 80Gi         | -                 |
| ml-team       | 5          | 40        | 80Gi         | 8 GPUs            |

### 6. Deploy vClusters

```bash
# Install vCluster CLI
curl -L -o vcluster "https://github.com/loft-sh/vcluster/releases/latest/download/vcluster-$(uname -s)-$(uname -m)"
sudo install -c -m 0755 vcluster /usr/local/bin

# Create namespaces for vClusters
kubectl create namespace tenant-customer-a
kubectl create namespace tenant-customer-b
kubectl create namespace tenant-customer-c

# Deploy virtual clusters
vcluster create customer-a -n tenant-customer-a -f vcluster/customer-a-values.yaml
vcluster create customer-b -n tenant-customer-b -f vcluster/customer-b-values.yaml
vcluster create customer-c -n tenant-customer-c -f vcluster/customer-c-values.yaml

# List all vClusters
vcluster list
```

## Testing Tenants

### Capsule: Namespace-based Isolation

```bash
# Create namespace as tenant owner
kubectl create namespace platform-team-dev \
  --as=system:serviceaccount:capsule-system:platform-team-sa

# Deploy workload
kubectl run nginx --image=nginx -n platform-team-dev

# Verify node scheduling
kubectl get pods -n platform-team-dev -o wide
# Pods should run on nodes with label: tenant-mode=soft-isolation

# Check resource quotas
kubectl describe resourcequota -n platform-team-dev

# Check tenant aggregate resources
kubectl get resourcequotas -A -l capsule.clastix.io/tenant=platform-team

# Test network isolation
kubectl exec -it nginx -n platform-team-dev -- curl data-team-service.data-team-dev
# Should fail due to network policies
```

### vCluster: Control Plane Isolation

```bash
# Connect to customer-a vCluster
vcluster connect customer-a -n tenant-customer-a

# Create namespace (inside virtual cluster)
kubectl create namespace production

# Deploy workload
kubectl run app --image=nginx -n production

# Check virtual cluster nodes
kubectl get nodes
# Shows virtual nodes, not host nodes

# Install custom CRDs (isolated to vCluster)
kubectl apply -f custom-operator.yaml

# Check vCluster Kubernetes version
kubectl version

# Disconnect from vCluster
vcluster disconnect

# Verify workload on host cluster
kubectl get pods -n tenant-customer-a
# Shows synced pods from vCluster
```

## Monitoring

### Access Grafana

```bash
# Port-forward Grafana
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80

# Default credentials: admin / admin
# Open: http://localhost:3000
```

### Key Metrics

```bash
# Check vCluster control plane resource usage
kubectl top pods -n tenant-customer-a
kubectl top pods -n tenant-customer-b
kubectl top pods -n tenant-customer-c

# Check Capsule tenant resource quotas
kubectl get resourcequotas -A -l capsule.clastix.io/tenant=platform-team
kubectl get resourcequotas -A -l capsule.clastix.io/tenant=data-team
kubectl get resourcequotas -A -l capsule.clastix.io/tenant=ml-team

# Check node resource allocation
kubectl describe nodes | grep -A 5 "Allocated resources"
```

## Comparison Matrix

| Feature               | Capsule          | vCluster              |
| --------------------- | ---------------- | --------------------- |
| **Isolation Level**   | Namespace (soft) | Control plane (hard)  |
| **API Server**        | Shared           | Dedicated per tenant  |
| **Resource Overhead** | ~50MB per tenant | ~200-500MB per tenant |
| **Provisioning Time** | 5-10 seconds     | 30-60 seconds         |
| **Cluster Admin**     | No               | Yes                   |
| **Custom CRDs**       | Shared           | Isolated              |
| **K8s Version**       | Same as host     | Independent           |
| **Network Policies**  | Shared rules     | Isolated              |
| **Use Case**          | Internal teams   | External customers    |
| **Cost (3 tenants)**  | +$20-40/month    | +$100-200/month       |

## Cost Savings

**vs. 3 Separate AKS Clusters:**

| Resource       | 3 AKS Clusters | This Demo  | Savings  |
| -------------- | -------------- | ---------- | -------- |
| Control Planes | 3 × $73/mo     | 1 × $73/mo | -$146    |
| System Nodes   | 6 nodes        | 2 nodes    | -4 nodes |
| **Total**      | ~$1,200/mo     | ~$400/mo   | **67%**  |

## Task Commands

```bash
# Infrastructure
task infra-apply         # Deploy AKS cluster with ArgoCD
task infra-destroy       # Destroy all resources
task verify-cluster      # Verify cluster connectivity
task verify-nodepools    # List node pools and labels

# Cluster info
task status              # Show cluster status
task nodes               # Show nodes with custom columns
task events-cluster      # Recent cluster events

# Cleanup
task clean               # Clean OpenTofu files
```

## GitOps Workflow

### Modify Platform Components

All platform components are managed by ArgoCD. To modify:

```bash
# Edit ArgoCD Application manifests
vim argocd/apps/capsule.yaml

# Apply changes
kubectl apply -f argocd/apps/capsule.yaml

# ArgoCD will automatically sync changes
kubectl get application capsule -n argocd -w
```

### Add New Tenant

```bash
# Create tenant manifest
cat > capsule/tenants/new-team.yaml <<EOF
apiVersion: capsule.clastix.io/v1beta2
kind: Tenant
metadata:
  name: new-team
spec:
  owners:
    - name: new-team-admin
      kind: Group
  nodeSelector:
    tenant-mode: soft-isolation
  namespaceOptions:
    quota: 5
  resourceQuotas:
    items:
      - hard:
          limits.cpu: "40"
          limits.memory: "80Gi"
EOF

# Apply tenant
kubectl apply -f capsule/tenants/new-team.yaml

# Verify
kubectl get tenant new-team
```

### Add New vCluster

```bash
# Create values file
cat > vcluster/customer-d-values.yaml <<EOF
controlPlane:
  distro:
    k3s:
      enabled: true
      image:
        tag: "v1.33.3-k3s1"
  statefulSet:
    resources:
      limits:
        cpu: "2"
        memory: "4Gi"
      requests:
        cpu: "200m"
        memory: "512Mi"
    scheduling:
      nodeSelector:
        workload-type: vcluster-control-plane
        tenant-mode: hard-isolation
    persistence:
      volumeClaim:
        enabled: true
        size: 10Gi
        storageClass: managed-premium
EOF

# Deploy vCluster
kubectl create namespace tenant-customer-d
vcluster create customer-d -n tenant-customer-d -f vcluster/customer-d-values.yaml
```

## Troubleshooting

### ArgoCD Applications

```bash
# Check application status
kubectl get applications -n argocd

# Describe specific application
kubectl describe application capsule -n argocd

# View application logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller

# Manually sync application
kubectl patch application capsule -n argocd \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

### Capsule Issues

```bash
# Check tenant status
kubectl describe tenant platform-team

# View Capsule controller logs
kubectl logs -n capsule-system -l app.kubernetes.io/name=capsule

# Check webhook configuration
kubectl get validatingwebhookconfiguration capsule-validating-webhook-configuration

# Check webhook endpoints
kubectl get endpoints -n capsule-system
```

### vCluster Issues

```bash
# Check vCluster pods
kubectl get pods -n tenant-customer-a
kubectl describe pod -n tenant-customer-a -l app=vcluster

# View syncer logs
kubectl logs -n tenant-customer-a -l app=vcluster -c syncer

# View control plane logs
kubectl logs -n tenant-customer-a -l app=vcluster -c vcluster

# Verify node selectors
kubectl get nodes --show-labels | grep vcluster-control-plane

# Check control plane resources
kubectl top pods -n tenant-customer-a
```

### Prometheus Stack Issues

```bash
# Check all monitoring pods
kubectl get pods -n monitoring

# Check Prometheus operator logs
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus-operator

# Check Prometheus logs
kubectl logs -n monitoring prometheus-prometheus-kube-prometheus-prometheus-0

# Verify CRDs
kubectl get crd | grep monitoring.coreos.com
```

### Common Issues

**ArgoCD application stuck in Progressing:**

```bash
# Check application events
kubectl describe application <app-name> -n argocd

# Force refresh
kubectl patch application <app-name> -n argocd --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"syncStrategy":{"hook":{}}}}}'
```

**Pods stuck pending:**

```bash
# Check node capacity
kubectl describe nodes | grep -A 5 "Allocated resources"

# Verify node selectors
kubectl get nodes -L tenant-mode,workload-type,nodepool-type
```

**Quota exceeded:**

```bash
# Capsule tenant
kubectl describe resourcequota -n <namespace>

# vCluster (inside virtual cluster)
vcluster connect <name> -n <namespace>
kubectl describe resourcequota -A
vcluster disconnect
```

**Network policy blocking traffic:**

```bash
# View network policies
kubectl get networkpolicies -A

# Check Capsule-managed policies
kubectl get networkpolicies -A -l capsule.clastix.io/tenant

# Describe specific policy
kubectl describe networkpolicy -n <namespace>
```

## Cleanup

```bash
# Delete vClusters
vcluster delete customer-a -n tenant-customer-a
vcluster delete customer-b -n tenant-customer-b
vcluster delete customer-c -n tenant-customer-c

# Delete Capsule tenants (cascades to namespaces)
kubectl delete tenant --all

# Delete ArgoCD applications
kubectl delete applications -n argocd --all

# Destroy infrastructure (includes ArgoCD)
task infra-destroy
```

## References

- [Capsule Documentation](https://capsule.clastix.io/)
- [vCluster Documentation](https://www.vcluster.com/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Kubernetes Multi-Tenancy SIG](https://github.com/kubernetes-sigs/multi-tenancy)
- [Blog Post: Building a Multi-Tenancy Platform](https://srekubecraft.io/posts/k8s-multi-tenancy/)
