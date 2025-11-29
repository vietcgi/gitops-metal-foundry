variable "tenancy_id" {
  description = "Tenancy OCID"
  type        = string
}

variable "compartment_id" {
  description = "Compartment OCID"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "user_ocid" {
  description = "User OCID for policy (optional)"
  type        = string
  default     = ""
}

variable "create_policy" {
  description = "Whether to create IAM policy"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
