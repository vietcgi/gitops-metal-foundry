variable "tenancy_id" {
  description = "OCI Tenancy OCID (budgets must be created at tenancy level)"
  type        = string
}

variable "compartment_id" {
  description = "OCI Compartment OCID to monitor"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "budget_amount" {
  description = "Monthly budget amount in USD"
  type        = number
  default     = 10
}

variable "alert_threshold" {
  description = "Alert when spending exceeds this amount in USD"
  type        = number
  default     = 1
}

variable "user_id" {
  description = "OCI User OCID to get email for alerts"
  type        = string
}

variable "tags" {
  description = "Freeform tags for resources"
  type        = map(string)
  default     = {}
}
