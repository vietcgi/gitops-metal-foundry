output "policy_id" {
  description = "Policy OCID (if created)"
  value       = var.create_policy ? oci_identity_policy.metal_foundry[0].id : null
}

output "policy_name" {
  description = "Policy name (if created)"
  value       = var.create_policy ? oci_identity_policy.metal_foundry[0].name : null
}
