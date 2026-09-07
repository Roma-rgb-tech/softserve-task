resource "google_monitoring_alert_policy" "threshold" {
  for_each = local.enabled == 1 ? local.policies : {}

  display_name          = "${local.prefix}: ${each.value.display}"
  combiner              = "OR"
  notification_channels = local.channels

  documentation {
    content   = each.value.documentation
    mime_type = "text/markdown"
  }

  conditions {
    display_name = each.value.display

    condition_threshold {
      filter          = "metric.type=\"${each.value.metric}\" AND resource.type=\"gce_instance\" AND ${local.owned}${each.value.extra}"
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.threshold
      duration        = "300s"

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_MAX"
        group_by_fields      = ["resource.label.instance_id"]
      }
    }
  }
}

# Availability is the absence of a signal rather than a bad value. Compute
# Engine reports instance/uptime for a running VM and nothing at all for one
# that is stopped, crashed or unreachable, so a missing series is the alert.
resource "google_monitoring_alert_policy" "availability" {
  count = local.enabled

  display_name          = "${local.prefix}: a VM stopped reporting"
  combiner              = "OR"
  notification_channels = local.channels

  documentation {
    content   = "A VM has sent no uptime samples for five minutes: it is stopped, crashed, or cut off from the network."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "No uptime samples for five minutes"

    condition_absent {
      filter   = "metric.type=\"compute.googleapis.com/instance/uptime\" AND resource.type=\"gce_instance\" AND ${local.owned}"
      duration = "300s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
}
