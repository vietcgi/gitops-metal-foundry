#=============================================================================
# Outputs
#=============================================================================

output "control_plane_public_ip" {
  description = "Public IP of the control plane VM"
  value       = module.control_plane.public_ip
}

output "control_plane_private_ip" {
  description = "Private IP of the control plane VM"
  value       = module.control_plane.private_ip
}

output "control_plane_id" {
  description = "OCID of the control plane VM"
  value       = module.control_plane.instance_id
}

output "vcn_id" {
  description = "OCID of the VCN"
  value       = module.vcn.vcn_id
}

output "public_subnet_id" {
  description = "OCID of the public subnet"
  value       = module.vcn.public_subnet_id
}

output "private_subnet_id" {
  description = "OCID of the private subnet"
  value       = module.vcn.private_subnet_id
}

# Note: State bucket (metal-foundry-state) is managed outside Terraform

# SSH command for convenience
output "ssh_command" {
  description = "SSH command to connect to control plane"
  value       = "ssh ubuntu@${module.control_plane.public_ip}"
}

# Cost summary
output "cost_summary" {
  description = "Monthly cost breakdown"
  value = {
    control_plane_vm = "$0.00 (Always Free: ${var.control_plane_shape})"
    boot_volume      = "$0.00 (Always Free: ${var.boot_volume_size_gb}GB)"
    networking       = "$0.00 (Always Free: VCN, subnets, NAT)"
    object_storage   = "$0.00 (Always Free: up to 10GB)"
    total            = "$0.00/month"
  }
}
