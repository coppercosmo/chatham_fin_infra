# Offline tests (mocked provider): the initiative is built from the real JSON files in policy/,
# starts in DoNotEnforce, gives remediation roles only where an effect needs them, and refuses
# exemptions that don't expire or aren't recorded in an ADR.

mock_provider "azurerm" {}

variables {
  definition_management_group_id = "/providers/Microsoft.Management/managementGroups/chatham"
  assignment_management_group_id = "/providers/Microsoft.Management/managementGroups/ai-advisory"
}

run "every_json_file_becomes_a_definition" {
  command = plan

  assert {
    condition     = length(azurerm_policy_definition.this) == length(fileset("${path.module}/../../../policy", "*.json"))
    error_message = "Each policy/*.json file must become exactly one custom definition."
  }

  assert {
    condition     = alltrue([for d in azurerm_policy_definition.this : startswith(d.display_name, "AI Advisory:")])
    error_message = "Custom definitions are prefixed 'AI Advisory:' so P&T can tell them apart from theirs."
  }
}

run "rolls_out_in_audit_mode_first" {
  command = plan

  assert {
    condition     = azurerm_management_group_policy_assignment.guardrails.enforce == false
    error_message = "The assignment must start in DoNotEnforce so the compliance report is read before anything is denied."
  }

  assert {
    condition = alltrue([for r in ["deny-ai-local-auth", "deny-ai-public-network", "deny-paas-public-network", "allowed-openai-skus", "require-rg-tags", "allowed-locations"] :
    contains(output.reference_ids, r)])
    error_message = "The initiative is missing one of the core guardrails."
  }

  assert {
    condition     = contains(output.reference_ids, "inherit-tag-client") && contains(output.reference_ids, "inherit-tag-cost_center")
    error_message = "Each required tag gets an inherit-from-resource-group rule."
  }

  # Modify (tags) needs Contributor at the assigned scope; no DNS rules means no Network Contributor.
  assert {
    condition     = keys(azurerm_role_assignment.remediation) == ["b24988ac-6180-42a0-ab88-20f7382dd24c"]
    error_message = "Without private DNS rules the identity should only get the role the tag rule declares."
  }

  assert {
    condition     = length(azurerm_role_assignment.dns_zones) == 0
    error_message = "No DNS rules, so no rights on P&T's DNS zones."
  }
}

run "private_dns_rules_get_rights_on_the_hub_zones" {
  command = plan

  variables {
    enforce = true
    private_dns_zones = {
      keyvault = {
        resource_type = "Microsoft.KeyVault/vaults"
        group_id      = "vault"
        zone_ids      = ["/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"]
      }
      openai = {
        resource_type = "Microsoft.CognitiveServices/accounts"
        group_id      = "account"
        zone_ids = [
          "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com",
          "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com",
        ]
      }
    }
    dns_zone_scope_ids = ["/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-dns"]
  }

  assert {
    condition     = contains(output.reference_ids, "private-dns-keyvault") && contains(output.reference_ids, "private-dns-openai")
    error_message = "One DeployIfNotExists rule per private endpoint type."
  }

  assert {
    condition     = contains(keys(azurerm_role_assignment.remediation), "4d97b98b-1d4f-4787-a291-c67834d212e7")
    error_message = "DeployIfNotExists declares Network Contributor, so the identity needs it at the assigned scope."
  }

  assert {
    condition     = azurerm_role_assignment.dns_zones["/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-dns"].role_definition_id == "/subscriptions/33333333-3333-3333-3333-333333333333/providers/Microsoft.Authorization/roleDefinitions/4d97b98b-1d4f-4787-a291-c67834d212e7"
    error_message = "The identity needs Network Contributor on the DNS zones' resource group to write records."
  }

  assert {
    condition     = azurerm_management_group_policy_assignment.guardrails.enforce == true
    error_message = "enforce = true switches the assignment to Default enforcement."
  }
}

run "exemption_without_expiry_is_refused" {
  command = plan

  variables {
    exemptions = {
      acme-public-storage = {
        subscription_id = "/subscriptions/22222222-2222-2222-2222-222222222222"
        reference_ids   = ["deny-paas-public-network"]
        category        = "Waiver"
        expires_on      = ""
        reason          = "ADR 0014: vendor upload needs a public endpoint for 30 days"
      }
    }
  }

  expect_failures = [var.exemptions]
}

run "exemption_without_adr_is_refused" {
  command = plan

  variables {
    exemptions = {
      acme-public-storage = {
        subscription_id = "/subscriptions/22222222-2222-2222-2222-222222222222"
        reference_ids   = ["deny-paas-public-network"]
        category        = "Waiver"
        expires_on      = "2027-01-31T00:00:00Z"
        reason          = "needed for a vendor upload"
      }
    }
  }

  expect_failures = [var.exemptions]
}

run "recorded_time_boxed_exemption_is_accepted" {
  command = plan

  variables {
    exemptions = {
      acme-public-storage = {
        subscription_id = "/subscriptions/22222222-2222-2222-2222-222222222222"
        reference_ids   = ["deny-paas-public-network"]
        category        = "Waiver"
        expires_on      = "2027-01-31T00:00:00Z"
        reason          = "ADR 0099 (example): vendor bulk upload needs a public endpoint until the 2027-01 cutover"
      }
    }
  }

  assert {
    condition     = azurerm_subscription_policy_exemption.this["acme-public-storage"].expires_on == "2027-01-31T00:00:00Z"
    error_message = "Exemption keeps its expiry."
  }
}
