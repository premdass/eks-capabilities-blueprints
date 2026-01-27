# ArgoCD Namespace Onboarding with kro

Automates namespace onboarding for ArgoCD deployments using ACK AccessEntries.

## What it does

When you create an `ArgoCDNamespace` CR, kro automatically creates:
- Namespace with ArgoCD labels
- ACK AccessEntry granting ArgoCD `AmazonEKSEditPolicy` scoped to that namespace

## Prerequisites

- kro capability enabled
- ArgoCD capability enabled
- ACK capability enabled
- Terraform applied (creates the `argocd-config` ConfigMap and applies this RGD)

## Deployed by Terraform

This RGD is automatically applied by Terraform in `capabilities.tf`. No manual kubectl apply needed.

## Usage

Create a namespace for ArgoCD to deploy to:

```yaml
apiVersion: kro.run/v1alpha1
kind: ArgoCDNamespace
metadata:
  name: my-app
  namespace: argocd  # Must be in argocd namespace
spec:
  namespace: my-app
```

That's it. No account IDs or role ARNs needed - kro reads them from the ConfigMap.

## Verify

```bash
kubectl get namespace my-app
kubectl get accessentry -n argocd
```

## How it works

1. Terraform creates a ConfigMap (`argocd-config` in `argocd` namespace) containing the ArgoCD role ARN and cluster name
2. kro RGD reads these values from the ConfigMap
3. When you create an `ArgoCDNamespace`, kro creates the namespace and an ACK AccessEntry
4. ACK creates an EKS access entry granting ArgoCD `AmazonEKSEditPolicy` scoped to that namespace

## Files

- `argocd-namespace-rgd.yaml` - The kro ResourceGraphDefinition
