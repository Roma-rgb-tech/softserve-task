# The Ops Agent ships every container's stdout to Cloud Logging under this log
# ID, parsed as JSON, so the application line sits in jsonPayload.log. The
# regex matches the status code an HTTP server writes after the request line,
# which is what a 5xx looks like in an access log of any of these services.
resource "google_logging_metric" "http_errors" {
  count = local.enabled

  name        = "${local.prefix}-http-5xx"
  description = "Responses with a 5xx status, counted from the container logs of every VM."

  filter = <<-EOT
    resource.type="gce_instance"
    log_id("${local.log_id}")
    jsonPayload.log=~"HTTP/1\\.1\" 5[0-9][0-9]"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_monitoring_alert_policy" "http_errors" {
  count = local.enabled

  display_name          = "${local.prefix}: ${local.errors} or more 5xx responses in five minutes"
  combiner              = "OR"
  notification_channels = local.channels

  documentation {
    content   = "The services are answering requests with server errors. The matching lines are in Logs Explorer under log_id(\"${local.log_id}\")."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "5xx responses in the container logs"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.http_errors[0].name}\" AND resource.type=\"gce_instance\""
      comparison      = "COMPARISON_GE"
      threshold_value = local.errors
      duration        = "0s"

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }
}
