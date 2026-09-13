variable "config" {
  description = "The whole project configuration, decoded from JSON. A vm with no public_endpoint, or one whose public_endpoint carries no cloudflare_zone_id, gets no DNS record from this module."
  type        = any
}

variable "vms" {
  description = "Merged workload map from the root module (module.gcp.vms + module.aws.vms), keyed by workload name. Only public_ip is read."
  type = map(object({
    public_ip = string
  }))
}
