# ArgoCD Access Entry

This kro RGD adds a Kubernetes group to ArgoCD's access entry, enabling custom RBAC bindings.

## Why is this needed?

The ArgoCD capability creates an access entry, but ArgoCD uses dynamic session names (`aws-go-sdk-<random>`) which makes it impossible to bind Kubernetes RBAC directly to the user. By adding a Kubernetes group to the access entry, we can bind RBAC to the group instead.

## How it works

1. The RGD reads `clusterName` and `argocdRoleArn` from the `argocd-config` ConfigMap (created by Terraform)
2. Uses ACK's `adopt-or-create` policy to adopt the capability-created access entry
3. Adds `kubernetesGroups: ["argocd-kro-access"]` to the access entry
4. The group can then be used in RoleBindings to grant ArgoCD custom permissions

## Prerequisites

1. ArgoCD capability must be created first
2. ACK capability must be installed
3. kro capability must be installed
4. `argocd-config` ConfigMap must exist in `argocd` namespace

## Deployed by Terraform

This RGD and its instance are automatically deployed by Terraform in `capabilities.tf`. No manual steps required.

## Verification

Check the access entry was updated:

```bash
aws eks describe-access-entry \
  --cluster-name <your-cluster-name> \
  --principal-arn <your-argocd-role-arn> \
  --region <your-region>
```

The `kubernetesGroups` field should include `argocd-kro-access`.
