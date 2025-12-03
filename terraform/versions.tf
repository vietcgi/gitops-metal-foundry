terraform {
  required_version = ">= 1.12.0" # Required for native OCI backend

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 7.27.0" # Nov 2025
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = ">= 2.3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.6" # Nov 2025
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5.2" # Nov 2025
    }
  }

  # State stored in OCI Object Storage (native backend)
  # Requires Terraform 1.12+ for native OCI backend support
  backend "oci" {
    # Configured via -backend-config or environment:
    #   -backend-config="bucket=metal-foundry-state"
    #   -backend-config="namespace=<your-namespace>"
    #   -backend-config="region=<your-region>"
    #   -backend-config="config_file_profile=<profile>"  # for local dev
  }
}

provider "oci" {
  region       = var.region
  tenancy_ocid = var.tenancy_ocid

  # API Key auth (CI/CD) - used when private_key is provided
  user_ocid   = var.private_key != "" ? var.user_ocid : null
  fingerprint = var.private_key != "" ? var.fingerprint : null
  private_key = var.private_key != "" ? var.private_key : null

  # CLI Session Token auth (local dev) - used when no private_key
  config_file_profile = var.private_key == "" ? var.oci_config_profile : null
  auth                = var.private_key == "" ? "SecurityToken" : "ApiKey"
}
