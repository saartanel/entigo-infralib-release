terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.38.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.7.2"
    }

  }
}
