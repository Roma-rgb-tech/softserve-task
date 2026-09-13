variable "project_config_path" {
  description = "Path to the external JSON file containing project-specific configuration."
  type        = string
  nullable    = false

  validation {
    condition     = fileexists(var.project_config_path)
    error_message = "project_config_path must point to an existing file."
  }
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token, scoped to Zone:DNS:Edit. Only required when a vm's public_endpoint sets cloudflare_zone_id. Set via TF_VAR_cloudflare_api_token, never in a config file."
  type        = string
  default     = ""
  sensitive   = true
}
