output "budget_id" {
  description = "The OCID of the budget"
  value       = oci_budget_budget.main.id
}

output "alert_rule_id" {
  description = "The OCID of the alert rule"
  value       = oci_budget_alert_rule.overspend.id
}
