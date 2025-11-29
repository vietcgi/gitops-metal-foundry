#=============================================================================
# GitOps Metal Foundry - Main Terraform Configuration
#
# This creates the Oracle Cloud infrastructure for the control plane.
# ALL resources use Always Free tier - $0/month guaranteed.
#=============================================================================

locals {
  # Common tags for all resources
  common_tags = {
    Project     = var.project_name
    Environment = "production"
    ManagedBy   = "terraform"
    CostCenter  = "free-tier"
  }

  # Determine if using AMD or ARM shape
  is_arm = var.control_plane_shape == "VM.Standard.A1.Flex"
}

#=============================================================================
# Data Sources
#=============================================================================

# Get availability domains
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# Get latest Ubuntu 24.04 LTS image
data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = var.control_plane_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"

  filter {
    name   = "display_name"
    values = ["^Canonical-Ubuntu-24\\.04-(aarch64-)?[\\d\\.]+$"]
    regex  = true
  }
}

#=============================================================================
# Networking Module
#=============================================================================

module "vcn" {
  source = "./modules/vcn"

  compartment_id      = var.compartment_ocid
  project_name        = var.project_name
  vcn_cidr            = var.vcn_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
  ssh_source_cidr     = var.ssh_source_cidr
  admin_source_cidr   = var.admin_source_cidr
  tags                = local.common_tags
}

#=============================================================================
# Compute Module - Control Plane
#=============================================================================

module "control_plane" {
  source = "./modules/compute"

  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  project_name        = var.project_name
  subnet_id           = module.vcn.public_subnet_id
  nsg_ids             = [module.vcn.control_plane_nsg_id]

  # Instance configuration
  shape          = var.control_plane_shape
  ocpus          = local.is_arm ? var.control_plane_ocpus : null
  memory_gb      = local.is_arm ? var.control_plane_memory_gb : null
  image_id       = data.oci_core_images.ubuntu.images[0].id
  ssh_public_key = var.ssh_public_key

  # Boot volume
  boot_volume_size_gb = var.boot_volume_size_gb

  # Cloud-init configuration
  tailscale_auth_key = var.tailscale_auth_key
  domain             = var.domain

  tags = local.common_tags
}

#=============================================================================
# Object Storage Module - For Terraform State & Backups
#=============================================================================

module "object_storage" {
  source = "./modules/object-storage"

  compartment_id = var.compartment_ocid
  project_name   = var.project_name
  tags           = local.common_tags
}

#=============================================================================
# IAM Module - Optional policies
#=============================================================================

module "iam" {
  source = "./modules/iam"

  tenancy_id     = var.tenancy_ocid
  compartment_id = var.compartment_ocid
  project_name   = var.project_name
  create_policy  = false # Not needed - using API key auth from GitHub Actions
  tags           = local.common_tags
}
