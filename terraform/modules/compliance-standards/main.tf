# Regulatory compliance standards for Microsoft Defender for Cloud (ADR 0016).
#
# PROPOSED TO PLATFORM ENGINEERING (ADR 0002), like policy-guardrails. P&T owns Defender for Cloud and
# policy assignments; this module is what we hand them. It:
#   - assigns built-in standards (SOC 2, ISO 27001, NIST 800-53 ...) at the AI Advisory management group,
#     so every platform, Tier 1, cell and pool subscription below it inherits them from minute one;
#   - assigns extra standards for one client where its contract or region needs them: at its subscription
#     (Tier 1) or its resource group in a cell (Tier 2);
#   - builds custom standards from policy/standards/*.json for frameworks with no built-in (NYDFS Part 500);
#   - records accepted gaps as time-boxed exemptions that cite an ADR.
#
# Standards REPORT; they never block. Every assignment is DoNotEnforce and its identity gets no roles. Blocking
# is the guardrails initiative's job (policy-guardrails), and P&T's baseline stays the only thing that deploys.

locals {
  custom_standards_path = coalesce(var.custom_standards_path, "${path.module}/../../../policy/standards")

  # policy/standards/<name>.json, decoded, for the custom standards asked for.
  custom = {
    for name in var.custom_standards :
    name => jsondecode(file("${local.custom_standards_path}/${name}.json"))
  }

  # One assignment per (scope, standard) pair. A scope is a subscription (Tier 1 client, or a whole cell or
  # pool) or a resource group (one client inside a cell).
  scoped = merge([
    for label, s in var.scoped_standards : {
      for std in s.standards : "${label}/${std}" => {
        label    = label
        standard = std
        scope_id = s.scope_id
        is_rg    = can(regex("(?i)/resourceGroups/[^/]+$", s.scope_id))
      }
    }
  ]...)

  scoped_subscription   = { for k, v in local.scoped : k => v if !v.is_rg }
  scoped_resource_group = { for k, v in local.scoped : k => v if v.is_rg }

  description = "Report only (DoNotEnforce). Proposed by AI Advisory, owned by Platform Engineering (ADR 0002, ADR 0016)."
}

# ------------------------------------------------------------------ built-in standards for the whole estate
resource "azurerm_management_group_policy_assignment" "standard" {
  for_each             = toset(var.standards)
  name                 = "std-${each.key}" # 24 characters max at management group scope (validated)
  display_name         = "${local.catalog[each.key].name} (AI Advisory)"
  description          = local.description
  management_group_id  = var.assignment_management_group_id
  policy_definition_id = "${local.initiative_prefix}/${local.catalog[each.key].guid}"
  enforce              = false
  location             = var.location
  metadata             = jsonencode({ category = "Regulatory Compliance", assignedBy = "AI Advisory (proposed to P&T)", status = local.catalog[each.key].status })

  # Some standards include DeployIfNotExists rules (MCSB v2 does), and Azure refuses such an assignment without
  # an identity. It gets no roles here, and DoNotEnforce means nothing is deployed.
  identity {
    type = "SystemAssigned"
  }
}

# ------------------------------------------------------------------ extra standards for one client
resource "azurerm_subscription_policy_assignment" "scoped" {
  for_each             = local.scoped_subscription
  name                 = "std-${each.value.standard}-${substr(sha1(each.key), 0, 8)}"
  display_name         = "${local.catalog[each.value.standard].name} (AI Advisory: ${each.value.label})"
  description          = local.description
  subscription_id      = each.value.scope_id
  policy_definition_id = "${local.initiative_prefix}/${local.catalog[each.value.standard].guid}"
  enforce              = false
  location             = var.location
  metadata             = jsonencode({ category = "Regulatory Compliance", client = each.value.label, status = local.catalog[each.value.standard].status })

  identity {
    type = "SystemAssigned"
  }
}

# Tier 2: one client's resource group in a cell. Defender's dashboard works per subscription or management
# group, so this reports in Azure Policy compliance and Resource Graph, filtered to the client's group.
resource "azurerm_resource_group_policy_assignment" "scoped" {
  for_each             = local.scoped_resource_group
  name                 = "std-${each.value.standard}-${substr(sha1(each.key), 0, 8)}"
  display_name         = "${local.catalog[each.value.standard].name} (AI Advisory: ${each.value.label})"
  description          = local.description
  resource_group_id    = each.value.scope_id
  policy_definition_id = "${local.initiative_prefix}/${local.catalog[each.value.standard].guid}"
  enforce              = false
  location             = var.location
  metadata             = jsonencode({ category = "Regulatory Compliance", client = each.value.label, status = local.catalog[each.value.standard].status })

  identity {
    type = "SystemAssigned"
  }
}

# ------------------------------------------------------------------ custom standards (no built-in exists)
# Built from built-in audit policies, grouped by the framework's sections, so Defender shows a score per
# section. metadata.ASC = "true" is how an Azure Policy initiative is onboarded to Defender as a standard
# (Microsoft calls this route legacy; its newer custom standards are built in the portal and have no
# Terraform resource yet).
resource "azurerm_management_group_policy_set_definition" "custom" {
  for_each            = local.custom
  name                = "ai-adv-${each.key}"
  policy_type         = "Custom"
  display_name        = each.value.displayName
  description         = each.value.description
  management_group_id = var.definition_management_group_id
  metadata = jsonencode({
    category = "Regulatory Compliance"
    ASC      = "true"
    version  = each.value.version
    source   = "chatham_fin_infra/policy/standards/${each.key}.json"
  })

  dynamic "policy_definition_group" {
    for_each = each.value.groups
    content {
      name         = policy_definition_group.key
      display_name = policy_definition_group.value
      category     = each.value.category
    }
  }

  dynamic "policy_definition_reference" {
    for_each = { for c in each.value.checks : c.ref => c }
    content {
      reference_id         = policy_definition_reference.key
      policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/${policy_definition_reference.value.id}"
      policy_group_names   = policy_definition_reference.value.groups
      parameter_values     = try(policy_definition_reference.value.effect, null) == null ? null : jsonencode({ effect = { value = policy_definition_reference.value.effect } })
    }
  }

  lifecycle {
    precondition {
      condition     = var.definition_management_group_id != null
      error_message = "Custom standards need definition_management_group_id: the management group that holds the initiative (usually P&T's intermediate root)."
    }
    precondition {
      condition     = alltrue(flatten([for c in each.value.checks : [for g in c.groups : contains(keys(each.value.groups), g)]]))
      error_message = "A check in policy/standards/${each.key}.json names a group that the file doesn't define."
    }
    precondition {
      condition     = alltrue([for c in each.value.checks : can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", c.id))])
      error_message = "Every check in policy/standards/${each.key}.json must be a built-in policy definition GUID."
    }
    precondition {
      condition     = length(distinct([for c in each.value.checks : c.ref])) == length(each.value.checks)
      error_message = "Check refs in policy/standards/${each.key}.json must be unique."
    }
  }
}

resource "azurerm_management_group_policy_assignment" "custom" {
  for_each             = local.custom
  name                 = "std-${each.key}"
  display_name         = each.value.displayName
  description          = local.description
  management_group_id  = var.assignment_management_group_id
  policy_definition_id = azurerm_management_group_policy_set_definition.custom[each.key].id
  enforce              = false
  location             = var.location
  metadata             = jsonencode({ category = "Regulatory Compliance", assignedBy = "AI Advisory (proposed to P&T)", status = "custom" })

  identity {
    type = "SystemAssigned"
  }
}

# ------------------------------------------------------------------ accepted gaps
# A known gap (for example customer-managed keys, which the stamps don't use yet) shows as Exempt with a
# reason and an end date, instead of a red control nobody can explain. Same rules as policy-guardrails.
resource "azurerm_subscription_policy_exemption" "this" {
  for_each                        = var.exemptions
  name                            = "exempt-${each.key}"
  display_name                    = "AI Advisory: ${each.key}"
  description                     = each.value.reason
  subscription_id                 = each.value.subscription_id
  policy_assignment_id            = azurerm_management_group_policy_assignment.standard[each.value.standard].id
  policy_definition_reference_ids = each.value.reference_ids
  exemption_category              = each.value.category
  expires_on                      = each.value.expires_on
}
