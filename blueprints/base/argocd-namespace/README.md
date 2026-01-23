# ArgoCD Namespace Onboarding with kro

Automates namespace onboarding for ArgoCD deployments.

## What it does

When you create an `ArgoCDNamespace` CR, kro automatically creates:
- Namespace with ArgoCD labels
- Role with write permissions (pods, deployments, services, etc.)
- RoleBinding granting ArgoCD access to the namespace

## Prerequisites

- kro capability enabled
- ArgoCD capability enabled  
- Terraform applied (creates the `argocd-config` ConfigMap in `default` namespace)

## Usage

### 1. Apply the ResourceGraphDefinition

```bash
kubectl apply -f blueprints/base/argocd-namespace/argocd-namespace-rgd.yaml
```

### 2. Create a namespace for ArgoCD

```yaml
apiVersion: kro.run/v1alpha1
kind: ArgoCDNamespace
metadata:
  name: my-app
spec:
  namespace: my-app
```

That's it. No account IDs or role ARNs needed - kro reads them from the ConfigMap.

### 3. Verify

```bash
kubectl get namespace my-app
kubectl get role argocd-deploy -n my-app
kubectl get rolebinding argocd-deploy -n my-app
```

## How it works

1. Terraform creates a ConfigMap (`argocd-config` in `default` namespace) containing the ArgoCD user ARN
2. kro RGD reads the ARN from the ConfigMap
3. When you create an `ArgoCDNamespace`, kro creates the namespace and RBAC binding to that ARN

## Files

- `argocd-namespace-rgd.yaml` - The kro ResourceGraphDefinition
