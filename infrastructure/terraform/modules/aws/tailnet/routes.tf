locals {
  routes = merge([
    for table in ["management", "workload"] : {
      for cloud, cidr in local.remote_cidrs :
      "${table}/${cloud}" => { table = table, cidr = cidr }
    }
  ]...)
}

resource "aws_route" "remote" {
  for_each = local.enabled ? local.routes : {}

  route_table_id         = var.route_table_ids[each.value.table]
  destination_cidr_block = each.value.cidr
  network_interface_id   = var.next_hop
}
