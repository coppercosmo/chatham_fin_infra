# AI Advisory guardrails as one Azure Policy initiative (policy set).
#
# PROPOSED TO PLATFORM ENGINEERING (ADR 0002). P&T owns management groups and policy assignments;
# this module is what we hand them, the same way hub-connectivity is. It turns the JSON files in
# policy/ into custom definitions, groups them with two built-ins into one initiative, and assigns
# it to the AI Advisory management group in DoNotEnforce mode until the compliance report is clean.

locals {
  definitions_path = coalesce(var.definitions_path, "${path.module}/../../../policy")

  # Every *.json file in policy/ becomes one custom definition, named after the file.
  definitions = {
    for f in fileset(local.definitions_path, "*.json") :
    trimsuffix(f, ".json") => jsondecode(file("${local.definitions_path}/${f}")).properties
  }

  # Built-in definitions are referenced by their fixed GUID. Prefer a built-in when one exists.
  builtin_allowed_locations = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"

  # What goes into the initiative. reference_id => definition + parameter values.
  references = merge(
    {
      "deny-ai-local-auth" = {
        custom     = "deny-cognitive-services-local-auth"
        parameters = { effect = "Deny" }
      }
      "deny-ai-public-network" = {
        custom     = "deny-cognitive-services-public-network"
        parameters = { effect = "Deny" }
      }
      "deny-paas-public-network" = {
        custom     = "deny-paas-public-network-access"
        parameters = { effect = "Deny" }
      }
      "allowed-openai-skus" = {
        custom     = "allowed-openai-deployment-skus"
        parameters = { effect = "Deny", allowedSkus = var.allowed_openai_deployment_skus }
      }
      "require-rg-tags" = {
        custom     = "require-resource-group-tags"
        parameters = { effect = "Deny", tagNames = var.required_tags }
      }
      "allowed-locations" = {
        builtin    = local.builtin_allowed_locations
        parameters = { listOfAllowedLocations = var.allowed_locations }
      }
    },
    {
      for t in var.required_tags : "inherit-tag-${t}" => {
        custom     = "inherit-tag-from-resource-group"
        parameters = { effect = "Modify", tagName = t }
      }
    },
    {
      for k, z in var.private_dns_zones : "private-dns-${k}" => {
        custom = "deploy-private-dns-zone-group"
        parameters = {
          effect            = "DeployIfNotExists"
          resourceType      = z.resource_type
          groupId           = z.group_id
          privateDnsZoneIds = z.zone_ids
        }
      }
    },
  )

  used_custom = toset([for r in local.references : r.custom if try(r.custom, null) != null])

  # The assignment's managed identity needs the roles that the DeployIfNotExists / Modify rules
  # declare in their roleDefinitionIds. Read them from the definitions so they can't drift.
  remediation_role_guids = distinct(flatten([
    for name in local.used_custom : [
      for id in try(local.definitions[name].policyRule.then.details.roleDefinitionIds, []) : reverse(split("/", id))[0]
    ]
  ]))
  network_contributor_guid = "4d97b98b-1d4f-4787-a291-c67834d212e7"
}

resource "azurerm_policy_definition" "this" {
  for_each            = local.definitions
  name                = each.key
  policy_type         = "Custom"
  mode                = each.value.mode
  display_name        = each.value.displayName
  description         = try(each.value.description, null)
  management_group_id = var.definition_management_group_id
  policy_rule         = jsonencode(each.value.policyRule)
  parameters          = jsonencode(each.value.parameters)
  metadata            = jsonencode({ category = "AI Advisory", source = "chatham_fin_infra/policy/${each.key}.json" })
}

resource "azurerm_management_group_policy_set_definition" "guardrails" {
  name                = "ai-advisory-guardrails"
  policy_type         = "Custom"
  display_name        = "AI Advisory guardrails"
  description         = "Private networking, keyless AI services, data-residency SKUs, regions, tags and private DNS for AI Advisory client subscriptions."
  management_group_id = var.definition_management_group_id
  metadata            = jsonencode({ category = "AI Advisory", version = "1.0.0" })

  dynamic "policy_definition_reference" {
    for_each = local.references
    content {
      reference_id         = policy_definition_reference.key
      policy_definition_id = try(policy_definition_reference.value.builtin, azurerm_policy_definition.this[policy_definition_reference.value.custom].id)
      parameter_values     = jsonencode({ for k, v in policy_definition_reference.value.parameters : k => { value = v } })
    }
  }

  lifecycle {
    precondition {
      condition     = alltrue([for name in local.used_custom : contains(keys(local.definitions), name)])
      error_message = "The initiative references a definition with no matching JSON file in ${local.definitions_path}."
    }
  }
}

resource "azurerm_management_group_policy_assignment" "guardrails" {
  name                 = "ai-adv-guardrails" # 24 characters max at management group scope
  display_name         = "AI Advisory guardrails"
  management_group_id  = var.assignment_management_group_id
  policy_definition_id = azurerm_management_group_policy_set_definition.guardrails.id
  enforce              = var.enforce
  location             = var.location

  identity {
    type = "SystemAssigned"
  }

  non_compliance_message {
    content = "Blocked by the AI Advisory guardrails (owned by Platform Engineering). See policy/README.md in chatham_fin_infra, or ask P&T for a time-boxed exemption recorded in an ADR."
  }

  non_compliance_message {
    content                        = "AI services must use managed identity, not API keys (ADR 0004)."
    policy_definition_reference_id = "deny-ai-local-auth"
  }

  non_compliance_message {
    content                        = "Model deployments must keep processing in the approved data zone; GlobalStandard is not allowed (ADR 0006)."
    policy_definition_reference_id = "allowed-openai-skus"
  }
}

# Roles for remediation (DeployIfNotExists writes DNS zone groups, Modify writes tags) at the
# assigned scope, where the resources are.
resource "azurerm_role_assignment" "remediation" {
  for_each           = toset(local.remediation_role_guids)
  scope              = var.assignment_management_group_id
  role_definition_id = "${var.assignment_management_group_id}/providers/Microsoft.Authorization/roleDefinitions/${each.value}"
  principal_id       = azurerm_management_group_policy_assignment.guardrails.identity[0].principal_id
  principal_type     = "ServicePrincipal"
}

# Writing a record into a zone in P&T's hub also needs rights on the zone itself.
resource "azurerm_role_assignment" "dns_zones" {
  for_each           = length(var.private_dns_zones) > 0 ? toset(var.dns_zone_scope_ids) : toset([])
  scope              = each.value
  role_definition_id = "${regex("^/subscriptions/[^/]+", each.value)}/providers/Microsoft.Authorization/roleDefinitions/${local.network_contributor_guid}"
  principal_id       = azurerm_management_group_policy_assignment.guardrails.identity[0].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_subscription_policy_exemption" "this" {
  for_each                        = var.exemptions
  name                            = "exempt-${each.key}"
  display_name                    = "AI Advisory: ${each.key}"
  description                     = each.value.reason
  subscription_id                 = each.value.subscription_id
  policy_assignment_id            = azurerm_management_group_policy_assignment.guardrails.id
  policy_definition_reference_ids = each.value.reference_ids
  exemption_category              = each.value.category
  expires_on                      = each.value.expires_on
}
