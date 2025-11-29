terraform {
  required_version = ">= 1.5.0" # Compatible with OCI Cloud Shell

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 7.27.0" # Nov 2025
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
}

provider "oci" {
  region           = var.region
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key      = var.private_key
}
