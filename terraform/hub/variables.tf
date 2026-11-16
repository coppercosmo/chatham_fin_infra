variable "subscription_id" {
  type        = string
  description = "P&T's connectivity subscription."
}

variable "location" {
  type    = string
  default = "eastus2"
}

variable "name" {
  type    = string
  default = "hub-eus2"
}

variable "address_space" {
  type        = string
  default     = "10.0.0.0/22"
  description = "Hub VNet. Layout below matches the hub values in terraform/clients/*/terraform.tfvars (firewall 10.0.0.4, DNS 10.0.1.4)."
}

variable "firewall_sku" {
  type        = string
  default     = "Premium"
  description = "Premium adds IDPS and TLS inspection, the usual choice for financial services. Standard is cheaper for a demo."
  validation {
    condition     = contains(["Standard", "Premium"], var.firewall_sku)
    error_message = "firewall_sku must be Standard or Premium."
  }
}

variable "expressroute_gateway" {
  description = "See modules/hub-connectivity. null = no ExpressRoute gateway."
  type        = object({ sku = optional(string, "ErGw1AZ") })
  default     = {}
}

variable "vpn_gateway" {
  description = "See modules/hub-connectivity. null = no VPN gateway."
  type = object({
    sku           = optional(string, "VpnGw2AZ")
    active_active = optional(bool, true)
  })
  default = {}
}

variable "clients" {
  type        = any
  default     = {}
  description = "Client code => hub request (each stamp's hub_connectivity_request output, plus firewall_priority). Typed and validated by modules/hub-connectivity."
}

variable "secrets_key_vault_id" {
  type        = string
  default     = null
  description = "P&T Key Vault holding vpn-psk-<client> and er-auth-<client> secrets. Required once a VPN or ExpressRoute client exists."
}

variable "tags" {
  type    = map(string)
  default = {}
}
