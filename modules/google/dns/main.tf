
locals {
  domain = var.parent_zone_id != "" ? data.google_dns_managed_zone.parent_zone[0].dns_name : var.parent_domain

  public_subdomain_name  = var.public_subdomain_name != "" ? var.public_subdomain_name : var.prefix
  private_subdomain_name = var.private_subdomain_name != "" ? var.private_subdomain_name : "${var.prefix}-int"

  pub_domain = var.create_public ? "${local.public_subdomain_name}.${local.domain}" : local.domain
  int_domain = var.create_private ? "${local.private_subdomain_name}.${local.domain}" : local.pub_domain

  zone     = var.parent_zone_id != "" ? data.google_dns_managed_zone.parent_zone[0].name : ""
  pub_zone = var.create_public ? google_dns_managed_zone.pub[0].name : local.zone
  int_zone = var.create_private ? google_dns_managed_zone.int[0].name : local.pub_zone
}


resource "google_dns_managed_zone" "pub" {
  count         = var.create_public ? 1 : 0
  name          = trimsuffix(replace(local.pub_domain, ".", "-"), "-")
  dns_name      = local.pub_domain
  labels        = {}
  visibility    = "public"
  force_destroy = true

  cloud_logging_config {
    enable_logging = false
  }
}

resource "google_dns_managed_zone" "int" {
  count         = var.create_private ? 1 : 0
  name          = trimsuffix(replace(local.int_domain, ".", "-"), "-")
  dns_name      = local.int_domain
  labels        = {}
  visibility    = "private"
  force_destroy = true

  dynamic "private_visibility_config" {
    for_each = length(var.vpc_ids) > 0 ? [1] : []
    content {
      dynamic "networks" {
        for_each = var.vpc_ids
        content {
          network_url = networks.value
        }
      }
    }
  }
}

resource "google_dns_managed_zone" "int_cert" {
  count         = var.create_private ? 1 : 0
  name          = "${local.int_zone}-cert"
  dns_name      = local.int_domain
  labels        = {}
  visibility    = "public"
  force_destroy = true

  cloud_logging_config {
    enable_logging = false
  }
}

resource "google_dns_record_set" "pub_ns" {
  count        = var.parent_zone_id != "" && var.create_public ? 1 : 0
  name         = local.pub_domain
  type         = "NS"
  ttl          = 300
  managed_zone = var.parent_zone_id
  rrdatas      = google_dns_managed_zone.pub[0].name_servers
}

resource "google_dns_record_set" "int_ns" {
  count        = var.parent_zone_id != "" && var.create_private ? 1 : 0
  name         = local.int_domain
  type         = "NS"
  ttl          = 300
  managed_zone = var.parent_zone_id
  rrdatas      = concat(google_dns_managed_zone.int[0].name_servers, google_dns_managed_zone.int_cert[0].name_servers)

}

resource "google_dns_record_set" "pub_cert" {
  count        = var.create_public ? 1 : 0
  name         = google_certificate_manager_dns_authorization.pub_cert[0].dns_resource_record[0].name
  managed_zone = local.pub_zone
  type         = google_certificate_manager_dns_authorization.pub_cert[0].dns_resource_record[0].type
  ttl          = 300
  rrdatas      = [google_certificate_manager_dns_authorization.pub_cert[0].dns_resource_record[0].data]
}

resource "google_dns_record_set" "int_cert" {
  count        = var.create_private ? 1 : 0
  name         = google_certificate_manager_dns_authorization.int_cert[0].dns_resource_record[0].name
  managed_zone = "${local.int_zone}-cert"
  type         = google_certificate_manager_dns_authorization.int_cert[0].dns_resource_record[0].type
  ttl          = 300
  rrdatas      = [google_certificate_manager_dns_authorization.int_cert[0].dns_resource_record[0].data]
}

resource "google_certificate_manager_dns_authorization" "pub_cert" {
  count  = var.create_public ? 1 : 0
  name   = local.pub_zone
  domain = trimsuffix(local.pub_domain, ".")
}

resource "google_certificate_manager_dns_authorization" "int_cert" {
  count    = var.create_private ? 1 : 0
  name     = local.int_zone
  location = data.google_client_config.this.region
  domain   = trimsuffix(local.int_domain, ".")
}

resource "google_certificate_manager_certificate" "pub_cert" {
  count = var.create_public ? 1 : 0
  name  = local.pub_zone
  managed {
    domains            = [trimsuffix(local.pub_domain, "."), "*.${trimsuffix(local.pub_domain, ".")}"]
    dns_authorizations = [google_certificate_manager_dns_authorization.pub_cert[0].id]
  }
}

resource "google_certificate_manager_certificate" "int_cert" {
  count    = var.create_private ? 1 : 0
  name     = local.int_zone
  location = data.google_client_config.this.region
  managed {
    domains            = [trimsuffix(local.int_domain, "."), "*.${trimsuffix(local.int_domain, ".")}"]
    dns_authorizations = [google_certificate_manager_dns_authorization.int_cert[0].id]
  }
}

resource "google_certificate_manager_certificate_map" "pub_cert" {
  count = var.create_public ? 1 : 0
  name  = local.pub_zone
}

resource "google_certificate_manager_certificate_map_entry" "pub_cert_1" {
  count        = var.create_public ? 1 : 0
  name         = "${local.pub_zone}-1"
  map          = google_certificate_manager_certificate_map.pub_cert[0].name
  certificates = [google_certificate_manager_certificate.pub_cert[0].id]
  hostname     = trimsuffix(local.pub_domain, ".")
}

resource "google_certificate_manager_certificate_map_entry" "pub_cert_2" {
  count        = var.create_public ? 1 : 0
  name         = "${local.pub_zone}-2"
  map          = google_certificate_manager_certificate_map.pub_cert[0].name
  certificates = [google_certificate_manager_certificate.pub_cert[0].id]
  hostname     = "*.${trimsuffix(local.pub_domain, ".")}"
}

resource "google_dns_policy" "dns_policy" {
  count                     = length(var.dns_policy_vpc_ids) > 0 ? 1 : 0
  name                      = var.prefix
  enable_inbound_forwarding = var.enable_inbound_forwarding
  enable_logging            = var.enable_logging

  dynamic "networks" {
    for_each = var.dns_policy_vpc_ids
    content {
      network_url = networks.value
    }
  }

  dynamic "alternative_name_server_config" {
    for_each = var.alternative_name_servers != null ? [1] : []
    content {
      dynamic "target_name_servers" {
        for_each = var.alternative_name_servers
        content {
          ipv4_address    = target_name_servers.value.ipv4_address
          forwarding_path = lookup(target_name_servers.value, "forwarding_path", null)
        }
      }
    }
  }
}