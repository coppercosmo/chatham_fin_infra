variable "subscription_id" {
  type = string
}

variable "prefix" {
  description = "Short workload name used in every resource name."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,9}$", var.prefix))
    error_message = "prefix: 3-10 lowercase letters/digits, starting with a letter (storage account names are strict)."
  }
}

variable "location" {
  type    = string
  default = "eastus2"
}

variable "address_space" {
  description = "VNet range, /22 or larger. Split into a /24 for workloads and a /24 for private endpoints."
  type        = string
  default     = "10.50.0.0/22"
  validation {
    condition     = can(cidrhost(var.address_space, 0)) && tonumber(split("/", var.address_space)[1]) <= 22
    error_message = "address_space must be a valid CIDR of /22 or larger."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
