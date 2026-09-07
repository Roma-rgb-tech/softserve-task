# Only the two guest metrics need the Ops Agent. CPU is reported by the
# hypervisor, so it keeps alerting even on a host where the agent died.
#
# memory/percent_used and disk/percent_used both carry a state label and report
# every state separately, so without the extra clause the alert would fire on
# free space as happily as on used space.
locals {
  policies = {
    cpu = {
      display   = "CPU above ${local.cpu}% for five minutes"
      metric    = "compute.googleapis.com/instance/cpu/utilization"
      extra     = ""
      threshold = local.cpu / 100
      documentation = join(" ", [
        "A VM has been busy for five minutes straight.",
        "Check what is running before resizing anything:",
        "a stuck retry loop looks exactly like real load.",
      ])
    }

    memory = {
      display   = "Memory above ${local.memory}% for five minutes"
      metric    = "agent.googleapis.com/memory/percent_used"
      extra     = " AND metric.labels.state=\"used\""
      threshold = local.memory
      documentation = join(" ", [
        "Used memory on a VM has stayed high for five minutes.",
        "This one comes from the Ops Agent - the hypervisor cannot see inside the guest.",
        "Silence here means the agent stopped, which the availability policy catches separately.",
      ])
    }

    disk = {
      display   = "Disk above ${local.disk}% for five minutes"
      metric    = "agent.googleapis.com/disk/percent_used"
      extra     = " AND metric.labels.state=\"used\""
      threshold = local.disk
      documentation = join(" ", [
        "A filesystem on a VM is filling up.",
        "Container images and logs are what usually fill it:",
        "docker system prune buys time, a bigger boot disk fixes it.",
      ])
    }
  }
}
