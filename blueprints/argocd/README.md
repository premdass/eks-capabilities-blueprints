# ArgoCD Blueprints

This folder contains blueprints for deploying applications using the ArgoCD EKS capability. Each blueprint is a self-contained example that you can apply directly to your EKS cluster with ArgoCD enabled.

## Prerequisites

- EKS cluster with ArgoCD capability enabled (see [cluster/terraform](../../cluster/terraform/))
- kubectl configured to access your cluster
- ArgoCD CLI (optional, for advanced operations)

## Available Blueprints

| Blueprint | Description |
|-----------|-------------|
| [simple-webapp](./simple-webapp/) | Deploys a basic nginx web application |

## Usage

1. Ensure your EKS cluster has the ArgoCD capability enabled
2. Navigate to the blueprint folder you want to deploy
3. Follow the README instructions in that folder
4. Apply the ArgoCD Application manifest to your cluster

## Adding New Blueprints

Each blueprint should be in its own subfolder with:
- `README.md` - Deployment instructions
- `application.yaml` - ArgoCD Application manifest
- `manifests/` - Kubernetes manifests to deploy
