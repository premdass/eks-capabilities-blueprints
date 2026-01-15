# Amazon Elastic Kubernetes Service (Amazon EKS) Capabilities Blueprints

## Motivation

[Amazon EKS Capabilities](https://docs.aws.amazon.com/eks/latest/userguide/capabilities.html) is a set of fully managed cluster features that help accelerate developer velocity and offload the complexity of building and scaling with Kubernetes. These capabilities run within Amazon EKS rather than on your worker nodes, eliminating the need to install, maintain, and scale critical platform components.

This repository includes blueprints demonstrating how to use the three Amazon EKS Capabilities:

| Capability | Description |
|------------|-------------|
| **AWS Controllers for Kubernetes (ACK)** | Manage AWS resources (S3, RDS, DynamoDB, etc.) using Kubernetes APIs and custom resources |
| **Argo CD** | GitOps-based continuous deployment using Git repositories as the source of truth |
| **kro (Kube Resource Orchestrator)** | Create custom Kubernetes APIs that compose multiple resources into higher-level abstractions |

These capabilities are designed to work together, enabling powerful platform engineering patterns like self-service infrastructure, GitOps workflows, and custom resource abstractions.

## Blueprint Structure

Each blueprint follows the same structure to help you better understand what's the motivation and the expected results:

| Concept        | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| Purpose        | Explains what the blueprint is about, and what problem is solving.                              |
| Requirements   | Any pre-requisites you might need to use the blueprint.                                         |
| Deploy         | The steps to follow to deploy the blueprint into an existing Kubernetes cluster.                |
| Results        | The expected results when using the blueprint.                                                  |

## How to use these Blueprints?

Before you get started, you need to have a Kubernetes cluster with Amazon EKS Capabilities enabled. This project includes a Terraform template to create a cluster with all three capabilities (ACK, ArgoCD, kro) pre-configured.

## Support & Feedback

> [!IMPORTANT]
> EKS Capabilities Blueprints is maintained by AWS Solution Architects. It is not part of an AWS
> service and support is provided as a best-effort by the community. To provide feedback,
> please use the [issues templates](https://github.com/aws-samples/eks-capabilities-blueprints/issues)
> provided. If you are interested in contributing, see the
> [Contribution guide](CONTRIBUTING.md).

### Requirements

* You need access to an AWS account with IAM permissions to create an Amazon EKS cluster
* AWS Identity Center enabled in your account (required for ArgoCD capability). Verify this is enabled in the AWS Console under IAM Identity Center.
* Install and configure the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
* Install the [Kubernetes CLI (kubectl)](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)
* Install the [Terraform CLI](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)

### Create an Amazon EKS Cluster with Capabilities using Terraform

The Terraform template in this repository creates:
- A VPC with public and private subnets
- An Amazon EKS cluster with a managed node group
- Karpenter for node autoscaling
- All three Amazon EKS Capabilities (ACK, ArgoCD, kro)
- AWS Identity Center user for ArgoCD authentication
- Required IAM roles and policies
- KMS encryption for Kubernetes secrets
- CloudWatch logging for cluster audit and security

To create the cluster, clone this repository and run:

```sh
cd cluster/terraform
export TF_VAR_region=$AWS_REGION

# If your Identity Center is in a different region than your cluster
export TF_VAR_idc_region=us-east-1  # adjust to your IDC region

terraform init
terraform apply -target="module.vpc" -auto-approve
terraform apply --auto-approve
```

Before you continue, verify your AWS account can launch Spot instances if you haven't already:

```sh
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com || true
```

Once complete (typically 15-20 minutes), configure kubectl:

```sh
aws eks --region $AWS_REGION update-kubeconfig --name eks-capabilities-blueprints
```

Verify the capabilities are active:

```sh
# Check ACK resources
kubectl api-resources | grep services.k8s.aws

# Check ArgoCD resources
kubectl api-resources | grep argoproj.io

# Check kro resources
kubectl api-resources | grep kro.run
```

Get the ArgoCD server URL:

```sh
terraform output argocd_server_url
```

### Terraform Cleanup

To remove all resources created by Terraform:

```sh
# First, delete any blueprint resources you've deployed
# For ArgoCD applications:
kubectl delete applications --all -n argocd

# For ACK resources (S3, RDS, etc.):
kubectl delete buckets --all
kubectl delete dbinstances --all
# ... delete other ACK resources as needed

# For kro resources:
kubectl delete --all -A -l kro.run/instance

# Delete Karpenter resources
kubectl delete --all nodeclaim
kubectl delete --all nodepool
kubectl delete --all ec2nodeclass

# Destroy Terraform resources
export TF_VAR_region=$AWS_REGION
terraform destroy -target="module.eks_blueprints_addons" --auto-approve
terraform destroy -target="module.eks" --auto-approve
terraform destroy --auto-approve
```

## Deploying a Blueprint

After you have a cluster with EKS Capabilities enabled, you can start testing each blueprint. Open the blueprint folder and follow the steps in the README.

### ArgoCD Blueprints
* [Simple Webapp](blueprints/argocd/simple-webapp/) - Deploy nginx using ArgoCD GitOps

## Supported Versions

| Resources/Tool  | Version             |
| --------------- | ------------------- |
| [Kubernetes](https://kubernetes.io/releases/)      | 1.34                |
| [Karpenter](https://github.com/aws/karpenter/releases)       | v1.8.3            |
| [Terraform](https://github.com/hashicorp/terraform/releases)       | v1.14.2            |
| [AWS Provider](https://github.com/hashicorp/terraform-provider-aws/releases)  | ~> 6.23             |
| [AWSCC Provider](https://github.com/hashicorp/terraform-provider-awscc/releases)  | >= 1.0             |
| [AWS EKS Module](https://github.com/terraform-aws-modules/terraform-aws-eks/releases)  | v21.14.0             |
| [EKS Blueprints Addons](https://github.com/aws-ia/terraform-aws-eks-blueprints-addons/releases)  | v1.23.0              |

## License

MIT-0 Licensed. See [LICENSE](/LICENSE).
