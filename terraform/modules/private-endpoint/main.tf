# One private endpoint for one sub-resource of one PaaS service.
# private_dns_zone_ids empty = landing-zone mode: P&T's deploy-if-not-exists policy
# attaches the DNS zone group, so we must not manage it (Terraform would fight the policy).

variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "subnet_id" { type = string }
variable "target_resource_id" { type = string }
variable "subresource_name" { type = string }
variable "tags" { type = map(string) }

variable "private_dns_zone_ids" {
  type    = list(string)
  default = []
}

resource "azurerm_private_endpoint" "this" {
  name                          = var.name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  subnet_id                     = var.subnet_id
  custom_network_interface_name = "${var.name}-nic"
  tags                          = var.tags

  private_service_connection {
    name                           = "${var.name}-psc"
    private_connection_resource_id = var.target_resource_id
    subresource_names              = [var.subresource_name]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = length(var.private_dns_zone_ids) > 0 ? [1] : []
    content {
      name                 = "default"
      private_dns_zone_ids = var.private_dns_zone_ids
    }
  }

  lifecycle {
    # In landing-zone mode the zone group is owned by Azure Policy.
    ignore_changes = [private_dns_zone_group]
  }
}

output "id" { value = azurerm_private_endpoint.this.id }
output "private_ip" { value = azurerm_private_endpoint.this.private_service_connection[0].private_ip_address }
