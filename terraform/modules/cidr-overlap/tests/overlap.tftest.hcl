run "distinct_ranges_pass" {
  command = plan
  variables {
    prefixes = {
      "acme spoke"     = ["10.100.4.0/22"]
      "acme network"   = ["192.168.0.0/16", "172.20.0.0/24"]
      "fabrikam spoke" = ["10.100.12.0/22"]
      "fabrikam (NAT)" = ["100.64.12.0/24"]
    }
  }
  assert {
    condition     = length(output.overlaps) == 0
    error_message = "Distinct ranges must not be reported."
  }
}

run "contained_and_partial_overlaps_are_found" {
  command = plan
  variables {
    prefixes = {
      "acme network"     = ["10.0.0.0/8"]
      "meridian network" = ["10.20.0.0/16"]     # inside acme's /8
      "spoke"            = ["10.100.7.0/24"]    # also inside the /8
      "edge"             = ["255.255.255.0/24"] # top of the address space, no clash
    }
  }
  assert {
    condition     = length(output.overlaps) == 2
    error_message = "Expected two clashes (both inside 10.0.0.0/8), got: ${join("; ", output.overlaps)}"
  }
}

run "same_owner_may_repeat_itself" {
  command = plan
  variables {
    prefixes = { "acme network" = ["10.0.0.0/16", "10.0.1.0/24"] }
  }
  assert {
    condition     = length(output.overlaps) == 0
    error_message = "Overlaps inside one owner's own list are not a routing conflict."
  }
}

run "ipv6_is_rejected" {
  command = plan
  variables {
    prefixes = { "x" = ["fd00::/8"] }
  }
  expect_failures = [var.prefixes]
}
