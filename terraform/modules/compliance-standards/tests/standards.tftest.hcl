# Offline tests (mocked provider): the default standards are assigned at the AI Advisory MG in report-only
# mode, per-client standards land on the right scope type, the custom NYDFS standard is built from the real
# JSON file with every check in a defined section, and accepted gaps must expire and cite an ADR.

mock_provider "azurerm" {}

variables {
  assignment_management_group_id = "/providers/Microsoft.Management/managementGroups/ai-advisory"
}

run "defaults_assign_the_core_standards_report_only" {
  command = plan

  assert {
    condition     = keys(azurerm_management_group_policy_assignment.standard) == ["iso27001-2022", "nist80053r5", "soc2"]
    error_message = "Defaults are SOC 2, ISO 27001:2022 and NIST 800-53 Rev. 5."
  }

  assert {
    condition     = alltrue([for a in azurerm_management_group_policy_assignment.standard : a.enforce == false])
    error_message = "Standards report only (DoNotEnforce); blocking is the guardrails initiative's job."
  }

  assert {
    condition     = alltrue([for a in azurerm_management_group_policy_assignment.standard : a.management_group_id == "/providers/Microsoft.Management/managementGroups/ai-advisory"])
    error_message = "Standards are assigned once, at the AI Advisory MG, so every client subscription inherits them."
  }

  assert {
    condition     = azurerm_management_group_policy_assignment.standard["soc2"].policy_definition_id == "/providers/Microsoft.Authorization/policySetDefinitions/4054785f-702b-4a98-9215-009cbd58b141"
    error_message = "SOC 2 Type 2 must point at the verified built-in initiative."
  }

  assert {
    condition     = alltrue([for a in azurerm_management_group_policy_assignment.standard : length(a.name) <= 24])
    error_message = "Management group assignment names are 24 characters at most."
  }

  assert {
    condition     = !contains(keys(azurerm_management_group_policy_assignment.standard), "mcsb")
    error_message = "MCSB is inherited from P&T's intermediate root, not assigned again here."
  }

  assert {
    condition     = length(azurerm_management_group_policy_set_definition.custom) == 0 && length(azurerm_subscription_policy_exemption.this) == 0
    error_message = "No custom standards or exemptions unless asked for."
  }
}

run "every_catalog_entry_is_a_builtin_initiative_guid" {
  command = plan

  assert {
    condition     = alltrue([for c in output.catalog : can(regex("^/providers/Microsoft.Authorization/policySetDefinitions/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", c.initiative_id))])
    error_message = "Catalog IDs are built-in policy set definition GUIDs."
  }

  assert {
    condition     = length(distinct([for c in output.catalog : c.initiative_id])) == length(output.catalog)
    error_message = "Two catalog keys point at the same initiative."
  }

  assert {
    condition     = alltrue([for c in output.catalog : contains(["ga", "preview", "thin", "superseded"], c.status)])
    error_message = "Every catalog entry says how far to trust its score."
  }

  assert {
    condition     = alltrue([for k in ["mcsb-v2", "eu-ai-act", "nist-ai-rmf", "ffiec-cat"] : output.catalog[k].status != "ga"])
    error_message = "Preview, thin and retired standards are flagged, not presented as full standards."
  }
}

run "client_specific_standards_land_on_the_clients_scope" {
  command = plan

  variables {
    scoped_standards = {
      # Tier 1: an EU bank in its own subscription
      fabrikam = {
        scope_id  = "/subscriptions/22222222-2222-2222-2222-222222222222"
        standards = ["dora", "eu-ai-act"]
      }
      # Tier 2: one client's resource group inside a cell
      northwind = {
        scope_id  = "/subscriptions/44444444-4444-4444-4444-444444444444/resourceGroups/rg-northwind-prd-eus2"
        standards = ["dora"]
      }
    }
  }

  assert {
    condition     = keys(azurerm_subscription_policy_assignment.scoped) == ["fabrikam/dora", "fabrikam/eu-ai-act"]
    error_message = "A Tier 1 client's extra standards are assigned at its subscription."
  }

  assert {
    condition     = keys(azurerm_resource_group_policy_assignment.scoped) == ["northwind/dora"]
    error_message = "A cell client's extra standards are assigned at its own resource group, not the shared cell."
  }

  assert {
    condition     = azurerm_resource_group_policy_assignment.scoped["northwind/dora"].resource_group_id == "/subscriptions/44444444-4444-4444-4444-444444444444/resourceGroups/rg-northwind-prd-eus2"
    error_message = "Wrong scope for the cell client's assignment."
  }

  assert {
    condition     = alltrue([for a in merge(azurerm_subscription_policy_assignment.scoped, azurerm_resource_group_policy_assignment.scoped) : a.enforce == false && length(a.name) <= 64])
    error_message = "Per-client standards are report only, with valid names."
  }
}

run "a_standard_already_inherited_from_the_mg_is_refused_per_client" {
  command = plan

  variables {
    scoped_standards = {
      fabrikam = {
        scope_id  = "/subscriptions/22222222-2222-2222-2222-222222222222"
        standards = ["soc2"]
      }
    }
  }

  expect_failures = [var.scoped_standards]
}

run "unknown_standard_is_refused" {
  command = plan

  variables {
    standards = ["soc2", "iso42001"]
  }

  expect_failures = [var.standards]
}

run "retired_ffiec_cat_is_refused_estate_wide" {
  command = plan

  variables {
    standards = ["soc2", "ffiec-cat"]
  }

  expect_failures = [var.standards]
}

run "custom_nydfs_standard_is_built_from_the_json_file" {
  command = plan

  variables {
    definition_management_group_id = "/providers/Microsoft.Management/managementGroups/chatham"
    custom_standards               = ["nydfs-part-500"]
  }

  assert {
    condition     = jsondecode(azurerm_management_group_policy_set_definition.custom["nydfs-part-500"].metadata).ASC == "true"
    error_message = "metadata.ASC = true is what onboards the initiative to Defender for Cloud as a standard."
  }

  assert {
    condition     = length(azurerm_management_group_policy_set_definition.custom["nydfs-part-500"].policy_definition_reference) == length(jsondecode(file("${path.module}/../../../policy/standards/nydfs-part-500.json")).checks)
    error_message = "Every check in the JSON file becomes one reference in the initiative."
  }

  assert {
    condition     = length(azurerm_management_group_policy_set_definition.custom["nydfs-part-500"].policy_definition_group) == 7
    error_message = "One group per NYDFS section covered (500.3, .5, .6, .7, .14, .15, .16)."
  }

  assert {
    condition     = azurerm_management_group_policy_assignment.custom["nydfs-part-500"].enforce == false && azurerm_management_group_policy_assignment.custom["nydfs-part-500"].name == "std-nydfs-part-500"
    error_message = "The custom standard is assigned at the MG, report only."
  }

  assert {
    condition     = output.assigned_standards["nydfs-part-500"].status == "custom"
    error_message = "Custom standards are labelled as such in the outputs."
  }
}

run "custom_standard_needs_a_definition_scope" {
  command = plan

  variables {
    custom_standards = ["nydfs-part-500"]
  }

  expect_failures = [azurerm_management_group_policy_set_definition.custom]
}

run "exemption_must_target_an_assigned_standard" {
  command = plan

  variables {
    exemptions = {
      acme-cmk = {
        standard        = "dora"
        subscription_id = "/subscriptions/22222222-2222-2222-2222-222222222222"
        reference_ids   = ["67121cc7-ff39-4ab8-b7e3-95b84dab487d"]
        category        = "Waiver"
        expires_on      = "2027-06-30T00:00:00Z"
        reason          = "ADR 0016: customer-managed keys are a known gap"
      }
    }
  }

  expect_failures = [var.exemptions]
}

run "exemption_without_adr_or_expiry_is_refused" {
  command = plan

  variables {
    exemptions = {
      acme-cmk = {
        standard        = "soc2"
        subscription_id = "/subscriptions/22222222-2222-2222-2222-222222222222"
        reference_ids   = ["67121cc7-ff39-4ab8-b7e3-95b84dab487d"]
        category        = "Waiver"
        expires_on      = ""
        reason          = "CMK later"
      }
    }
  }

  expect_failures = [var.exemptions]
}

run "recorded_cmk_gap_is_exempt_until_it_expires" {
  command = plan

  variables {
    exemptions = {
      acme-cmk = {
        standard        = "soc2"
        subscription_id = "/subscriptions/22222222-2222-2222-2222-222222222222"
        reference_ids   = ["67121cc7-ff39-4ab8-b7e3-95b84dab487d", "6fac406b-40ca-413b-bf8e-0bf964659c25"]
        category        = "Waiver"
        expires_on      = "2027-06-30T00:00:00Z"
        reason          = "ADR 0016: customer-managed keys are a known gap (README); planned with self-hosted runners"
      }
    }
  }

  assert {
    condition     = azurerm_subscription_policy_exemption.this["acme-cmk"].expires_on == "2027-06-30T00:00:00Z"
    error_message = "The exemption keeps its expiry date."
  }

  assert {
    condition     = toset(azurerm_subscription_policy_exemption.this["acme-cmk"].policy_definition_reference_ids) == toset(["67121cc7-ff39-4ab8-b7e3-95b84dab487d", "6fac406b-40ca-413b-bf8e-0bf964659c25"])
    error_message = "Only the CMK rules are exempt, not the whole standard."
  }
}
