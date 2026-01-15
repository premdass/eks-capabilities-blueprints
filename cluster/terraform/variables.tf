## NOTE: It's going to use your AWS_REGION or AWS_DEFAULT_REGION environment variable,
## but you can define which on to use in terraform.tfvars file as well, or pass it as an argument
## in the CLI like this "terraform apply -var 'region=eu-west-1'"
variable "region" {
  description = "Region to deploy the resources"
  type        = string
}

#---------------------------------------------------------------
# ArgoCD Admin User Configuration
#---------------------------------------------------------------

variable "argocd_admin_username" {
  description = "Username for ArgoCD admin user in Identity Center"
  type        = string
  default     = "argocd-admin"
}

variable "argocd_admin_display_name" {
  description = "Display name for ArgoCD admin user"
  type        = string
  default     = "ArgoCD Admin"
}

variable "argocd_admin_given_name" {
  description = "Given name for ArgoCD admin user"
  type        = string
  default     = "ArgoCD"
}

variable "argocd_admin_family_name" {
  description = "Family name for ArgoCD admin user"
  type        = string
  default     = "Admin"
}

variable "argocd_admin_email" {
  description = "Email for ArgoCD admin user"
  type        = string
  default     = "admin@example.com"
}

variable "idc_region" {
  description = "AWS region where Identity Center is enabled. If not set, defaults to var.region"
  type        = string
  default     = null
}
