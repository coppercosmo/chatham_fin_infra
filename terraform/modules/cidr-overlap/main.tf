# Finds overlapping IPv4 ranges between different owners. Pure Terraform, no provider.
#
# Overlap is the most common reason a client network can't be routed into a shared hub: if two
# clients both use 10.0.0.0/16 at home, or a client uses the same range as their spoke, the hub's
# routers can't tell where a reply should go. The stamp and the hub module both run this check
# and refuse to plan when it finds a clash (fix: NAT on the VPN gateway, or Private Link instead).

variable "prefixes" {
  description = "Owner => list of IPv4 CIDRs, e.g. { \"acme spoke\" = [\"10.100.4.0/22\"], \"acme network\" = [\"192.168.0.0/16\"] }."
  type        = map(list(string))

  validation {
    condition     = alltrue(flatten([for ps in values(var.prefixes) : [for p in ps : can(cidrhost(p, 0)) && length(split(":", p)) == 1]]))
    error_message = "Every prefix must be an IPv4 CIDR such as 10.0.0.0/16."
  }
}

locals {
  flat = flatten([for owner, ps in var.prefixes : [for p in ps : { owner = owner, cidr = p }]])

  # Each range as [first address, size] in 32-bit integer form.
  ranges = [for e in local.flat : merge(e, {
    start = sum([for i, octet in split(".", cidrhost(e.cidr, 0)) : tonumber(octet) * pow(256, 3 - i)])
    size  = pow(2, 32 - tonumber(split("/", e.cidr)[1]))
  })]

  overlaps = distinct([
    for pair in setproduct(range(length(local.ranges)), range(length(local.ranges))) :
    "${local.ranges[pair[0]].owner} ${local.ranges[pair[0]].cidr} overlaps ${local.ranges[pair[1]].owner} ${local.ranges[pair[1]].cidr}"
    if pair[0] < pair[1] &&
    local.ranges[pair[0]].owner != local.ranges[pair[1]].owner &&
    local.ranges[pair[0]].start < local.ranges[pair[1]].start + local.ranges[pair[1]].size &&
    local.ranges[pair[1]].start < local.ranges[pair[0]].start + local.ranges[pair[0]].size
  ])
}

output "overlaps" {
  description = "One line per clash between two different owners. Empty when everything is distinct."
  value       = local.overlaps
}
