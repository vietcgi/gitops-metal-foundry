#=============================================================================
# IAM Module - Permissions for Metal Foundry Resources
#
# Note: GitHub Actions authenticates via API key (stored in GitHub Secrets).
# OCI does NOT support GitHub Actions OIDC like AWS/Azure/GCP.
#
# This module creates policies for managing resources in the compartment.
#=============================================================================

terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

locals {
  # Policy statements for the compartment
  policy_statements = [
    # Manage compute instances
    "Allow any-user to manage instance-family in compartment id ${var.compartment_id} where request.principal.id = '${var.user_ocid}'",

    # Manage networking
    "Allow any-user to manage virtual-network-family in compartment id ${var.compartment_id} where request.principal.id = '${var.user_ocid}'",

    # Manage object storage (for Terraform state)
    "Allow any-user to manage object-family in compartment id ${var.compartment_id} where request.principal.id = '${var.user_ocid}'",

    # Manage load balancers
    "Allow any-user to manage load-balancers in compartment id ${var.compartment_id} where request.principal.id = '${var.user_ocid}'",
  ]
}

#-----------------------------------------------------------------------------
# IAM Policy - Optional, only if using a service account
#-----------------------------------------------------------------------------

resource "oci_identity_policy" "metal_foundry" {
  count = var.create_policy ? 1 : 0

  compartment_id = var.tenancy_id
  name           = "${var.project_name}-policy"
  description    = "Permissions for Metal Foundry infrastructure management"

  statements = local.policy_statements

  freeform_tags = var.tags
}
