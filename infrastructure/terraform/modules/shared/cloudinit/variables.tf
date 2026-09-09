variable "machines" {
  description = "Per machine: the data disks to prepare, the commands to run at first boot, and any script from the configuration. A machine with none of them gets no cloud-init at all."
  type = map(object({
    hostname = string
    startup  = optional(string)
    commands = optional(list(string), [])
    disks = list(object({
      name       = string
      size_gb    = number
      mount_path = string
    }))
  }))
}
