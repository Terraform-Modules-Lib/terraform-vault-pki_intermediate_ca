terraform {
  required_version = "~> 0.14"
  
  required_providers {
    vault = {
      source = "hashicorp/vault"
      version = "~> 2.19"
    }
  }
}

locals {
  path = coalesce(var.path, var.name)
  description = coalesce(var.description, "${var.name} Certificate Authority")
  parent_authority_path = var.parent_ca
  urls_prefix = var.urls_prefix
}

# Enable mount point
resource "vault_mount" "this" {
  type = "pki"
  
  path = local.path
  description = local.description
}

# Create a CSR that will be signed from parent CA
resource "vault_pki_secret_backend_intermediate_cert_request" "this" {
  depends_on = [vault_mount.this]

  backend = vault_mount.this.path

  type = "internal"
  common_name = vault_mount.this.description
}

# Signing CSR from parent CA
resource "vault_pki_secret_backend_root_sign_intermediate" "this" {
  depends_on = [vault_pki_secret_backend_intermediate_cert_request.this]

  backend = local.parent_authority_path

  csr = vault_pki_secret_backend_intermediate_cert_request.this.csr
  common_name = vault_pki_secret_backend_intermediate_cert_request.this.common_name
}

# Set signed certificate
resource "vault_pki_secret_backend_intermediate_set_signed" "this" {
  depends_on = [vault_pki_secret_backend_root_sign_intermediate.this]
  
  backend = vault_mount.this.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.this.certificate
}

# and set URLs
resource "vault_pki_secret_backend_config_urls" "this" {
  depends_on = [vault_pki_secret_backend_intermediate_set_signed.this]
  
  for_each = local.urls_prefix
  
  backend = vault_pki_secret_backend_intermediate_set_signed.this.backend
  
  issuing_certificates = [ for url in local.urls_prefix: "${url}/v1/${vault_mount.this.path}/ca" ]
  crl_distribution_points = [ for url in local.urls_prefix: "${url}/v1/${vault_mount.this.path}/crl" ]
}
