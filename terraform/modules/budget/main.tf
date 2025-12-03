#=============================================================================
# Budget Module - Cost Alert
#
# Creates a budget with alert rule to notify when spending exceeds threshold.
# Uses the account user's email for notifications.
#=============================================================================

terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

# Get user email from the account
data "oci_identity_user" "current" {
  user_id = var.user_id
}

resource "oci_budget_budget" "main" {
  compartment_id = var.tenancy_id
  amount         = var.budget_amount
  reset_period   = "MONTHLY"
  display_name   = "${var.project_name}-budget"
  description    = format("Budget alert for %s - alerts when spending exceeds $%d", var.project_name, var.alert_threshold)

  # Target the specific compartment
  target_type = "COMPARTMENT"
  targets     = [var.compartment_id]

  freeform_tags = var.tags
}

resource "oci_budget_alert_rule" "overspend" {
  budget_id      = oci_budget_budget.main.id
  type           = "ACTUAL"
  threshold      = (var.alert_threshold / var.budget_amount) * 100
  threshold_type = "PERCENTAGE"
  display_name   = "${var.project_name}-overspend-alert"
  message        = format("WARNING: %s spending has exceeded $%d. Review OCI console for details.", var.project_name, var.alert_threshold)
  recipients     = data.oci_identity_user.current.email

  freeform_tags = var.tags
}
