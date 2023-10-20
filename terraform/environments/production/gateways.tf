# Deploy our dogfood gateways
resource "google_compute_network" "gateways" {
  project = module.google-cloud-project.project.project_id
  name    = "gateways"

  routing_mode = "GLOBAL"

  auto_create_subnetworks = false

  depends_on = [
    google_project_service.compute
  ]
}

module "gateways" {
  count = var.gateway_portal_token != null ? 1 : 0

  source     = "../../modules/gateway-app"
  project_id = module.google-cloud-project.project.project_id

  compute_network = "projects/${module.google-cloud-project.project.project_id}/global/networks/default"

  compute_instances = {
    "us-central1" = {
      type     = "n1-standard-1"
      replicas = 2
      zones    = ["us-central1-b"]

      network       = google_compute_network.gateways.self_link
      ip_cidr_range = "10.200.0.0/24"
    }
  }

  container_registry = module.google-artifact-registry.url

  image_repo = module.google-artifact-registry.repo
  image      = "gateway"
  image_tag  = var.gateway_image_tag

  observability_log_level = "debug"

  application_name    = "gateway"
  application_version = replace(var.gateway_image_tag, ".", "-")

  health_check = {
    name     = "health"
    protocol = "TCP"
    port     = 8080

    initial_delay_sec = 60

    check_interval_sec  = 15
    timeout_sec         = 10
    healthy_threshold   = 1
    unhealthy_threshold = 3

    http_health_check = {
      request_path = "/healthz"
    }
  }

  portal_websocket_url = "wss://api.${local.tld}"
  portal_token         = var.gateway_portal_token
}


# Allow inbound traffic
# resource "google_compute_firewall" "ingress-ipv4" {
#   count = var.gateway_portal_token != null ? 1 : 0

#   project = module.google-cloud-project.project.project_id

#   name      = "gateways-ingress-ipv4"
#   network   = google_compute_network.network.self_link
#   direction = "INGRESS"

#   target_tags   = module.gateways[0].target_tags
#   source_ranges = ["0.0.0.0/0"]

#   allow {
#     protocol = "udp"
#   }
# }

# resource "google_compute_firewall" "ingress-ipv6" {
#   count = var.gateway_portal_token != null ? 1 : 0

#   project = module.google-cloud-project.project.project_id

#   name      = "gateways-ingress-ipv6"
#   network   = google_compute_network.network.self_link
#   direction = "INGRESS"

#   target_tags   = module.gateways[0].target_tags
#   source_ranges = ["::/0"]

#   allow {
#     protocol = "udp"
#   }
# }

# Allow outbound traffic
resource "google_compute_firewall" "egress-ipv4" {
  count = var.gateway_portal_token != null ? 1 : 0

  project = module.google-cloud-project.project.project_id

  name      = "gateways-egress-ipv4"
  network   = google_compute_network.gateways.self_link
  direction = "EGRESS"

  target_tags        = module.gateways[0].target_tags
  destination_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "udp"
  }
}

resource "google_compute_firewall" "egress-ipv6" {
  count = var.gateway_portal_token != null ? 1 : 0

  project = module.google-cloud-project.project.project_id

  name      = "gateways-egress-ipv6"
  network   = google_compute_network.gateways.self_link
  direction = "EGRESS"

  target_tags        = module.gateways[0].target_tags
  destination_ranges = ["::/0"]

  allow {
    protocol = "udp"
  }
}

resource "google_compute_firewall" "gateways-ssh-ipv4" {
  count = length(module.gateways) > 0 ? 1 : 0

  project = module.google-cloud-project.project.project_id

  name    = "gateways-ssh-ipv4"
  network = module.google-cloud-vpc.self_link

  allow {
    protocol = "tcp"
    ports    = [22]
  }

  allow {
    protocol = "udp"
    ports    = [22]
  }

  allow {
    protocol = "sctp"
    ports    = [22]
  }

  # Only allows connections using IAP
  source_ranges = ["35.235.240.0/20"]
  target_tags   = module.gateways[0].target_tags
}