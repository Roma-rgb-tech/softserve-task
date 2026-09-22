terraform {
  required_version = "~> 1.15.1"

  backend "gcs" {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.44.0"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.20"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.40"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.2"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}
