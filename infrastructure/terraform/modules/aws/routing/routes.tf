locals {
  route_tables = {
    for name, table in {
      management = {
        subnet_id = lookup(var.subnets, "management", null)
        routes    = [{ cidr_block = "0.0.0.0/0", gateway_id = var.internet_gateway_id, nat_gateway_id = null }]
      }
      workload = {
        subnet_id = lookup(var.subnets, "workload", null)
        routes    = [{ cidr_block = "0.0.0.0/0", gateway_id = null, nat_gateway_id = one(aws_nat_gateway.main[*].id) }]
      }
    } : name => table if local.enabled
  }
}
