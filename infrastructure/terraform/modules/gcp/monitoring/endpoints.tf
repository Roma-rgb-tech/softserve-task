locals {
  endpoints = {
    for name, vm in var.config.vms : name => tostring(sort(var.config.network.ui_public_ports)[0])
    if lookup(vm, "cloud", local.default) == local.cloud
    && lookup(vm, "public_endpoint", null) != null
    && lookup(vm, "assign_public_ip", false)
  }
}

resource "google_monitoring_uptime_check_config" "endpoint" {
  for_each = local.enabled == 1 ? local.endpoints : {}

  display_name = "${local.prefix}-${each.key}"
  timeout      = "10s"
  period       = "300s"

  tcp_check {
    port = tonumber(each.value)
  }

  monitored_resource {
    type = "uptime_url"

    labels = {
      project_id = lookup(lookup(var.config, "gcp", {}), "project_id", "")
      host       = var.public_ips[each.key]
    }
  }
}

resource "google_monitoring_alert_policy" "endpoint" {
  for_each = google_monitoring_uptime_check_config.endpoint

  display_name          = "${local.prefix}: ${each.key} not answering from outside"
  combiner              = "OR"
  notification_channels = local.channels

  documentation {
    content   = "The public endpoint on ${each.key} stopped answering the uptime probes. The VM may still be up - this is the path through it that is broken."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Uptime check failing"

    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\" AND metric.labels.check_id=\"${each.value.uptime_check_id}\""
      comparison      = "COMPARISON_LT"
      threshold_value = 1
      duration        = "300s"

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_FRACTION_TRUE"
        cross_series_reducer = "REDUCE_MEAN"
      }
    }
  }
}
