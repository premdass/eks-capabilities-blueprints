# Simple Webapp Blueprint

This blueprint deploys a basic nginx web application to your Amazon Elastic Kubernetes Service (Amazon EKS) cluster using ArgoCD.

## Overview

- **Application**: nginx web server (unprivileged)
- **Namespace**: simple-webapp
- **Service Type**: ClusterIP (internal access)

## Prerequisites

1. Amazon EKS cluster with ArgoCD capability enabled
2. kubectl configured to access your cluster
3. Access to apply ArgoCD Application resources

## Deployment

### Step 1: Apply the ArgoCD Application

```bash
kubectl apply -f application.yaml
```

### Step 2: Verify the Application

Check the application status in ArgoCD:

```bash
kubectl get application simple-webapp -n argocd
```

### Step 3: Access the Application

The nginx service is exposed as ClusterIP. To access it locally:

```bash
kubectl port-forward svc/nginx -n simple-webapp 8080:80
```

Then open http://localhost:8080 in your browser.

## What Gets Deployed

| Resource | Name | Description |
|----------|------|-------------|
| Namespace | simple-webapp | Dedicated namespace for the application |
| Deployment | nginx | nginx web server with 1 replica (security-hardened) |
| Service | nginx | ClusterIP service exposing port 80 |

## Security Features

The deployment includes security best practices:
- Runs as non-root user
- Read-only root filesystem
- Drops all Linux capabilities
- Disables privilege escalation
- Uses seccomp runtime/default profile
- Disables service account token auto-mounting

## Sync Policy

The ArgoCD Application is configured with:
- **Automated Sync**: Changes in the repo are automatically applied
- **Self-Heal**: Drift from desired state is automatically corrected
- **Prune**: Resources removed from the repo are deleted from the cluster

## Cleanup

To remove the application:

```bash
kubectl delete -f application.yaml
```

This deletes the ArgoCD Application and all managed resources (namespace, deployment, service).
