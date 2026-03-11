terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }

    volterra = {
      source  = "volterraedge/volterra"
      version = ">= 0.11.42"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.4.0"
    }
  }
}
