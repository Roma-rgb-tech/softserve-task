locals {
  gauge = { aligner = "ALIGN_MEAN", reducer = "REDUCE_MAX", group_by = ["resource.label.instance_id"] }
  delta = { aligner = "ALIGN_DELTA", reducer = "REDUCE_SUM", group_by = [] }

  charts = [
    merge(local.gauge, { title = "CPU utilisation", metric = "compute.googleapis.com/instance/cpu/utilization", extra = "" }),
    merge(local.gauge, { title = "Memory used, %", metric = "agent.googleapis.com/memory/percent_used", extra = " AND metric.labels.state=\"used\"" }),
    merge(local.gauge, { title = "Disk used, %", metric = "agent.googleapis.com/disk/percent_used", extra = local.used_disk }),
    merge(local.gauge, { title = "Uptime", metric = "compute.googleapis.com/instance/uptime", extra = "" }),
    merge(local.delta, { title = "Network received", metric = "compute.googleapis.com/instance/network/received_bytes_count", extra = "" }),
    merge(local.delta, { title = "5xx responses", metric = "logging.googleapis.com/user/${local.prefix}-http-5xx", extra = "" }),
  ]

  tiles = [
    for index, chart in local.charts : {
      width  = 6
      height = 4
      xPos   = index % 2 * 6
      yPos   = floor(index / 2) * 4

      widget = {
        title = chart.title

        xyChart = {
          dataSets = [{
            plotType = "LINE"

            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = "metric.type=\"${chart.metric}\" AND resource.type=\"gce_instance\"${chart.extra}"

                aggregation = {
                  alignmentPeriod    = "300s"
                  perSeriesAligner   = chart.aligner
                  crossSeriesReducer = chart.reducer
                  groupByFields      = chart.group_by
                }
              }
            }
          }]
        }
      }
    }
  ]
}

resource "google_monitoring_dashboard" "overview" {
  count = local.enabled

  dashboard_json = jsonencode({
    displayName  = "${local.prefix} overview"
    mosaicLayout = { columns = 12, tiles = local.tiles }
  })
}
