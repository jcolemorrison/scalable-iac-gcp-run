# Create Cloud Run services
resource "google_cloud_run_v2_service" "client" {
  count    = length(var.deployment_regions)
  name     = format("service-%s-%d", var.deployment_regions[count.index], count.index + 1)
  location = var.deployment_regions[count.index]

  template {
    containers {
      image = "nicholasjackson/fake-service:v0.26.0"

      env {
        name  = "MESSAGE"
        value = "Hello from the client in the ${var.deployment_regions[count.index]} region"
      }

      env {
        name  = "NAME"
        value = "Client"
      }

      env {
        name  = "LISTEN_ADDR"
        value = "0.0.0.0:8080"
      }
    }

    vpc_access {
      connector = google_vpc_access_connector.vpc_connector[count.index].id
      egress    = "ALL_TRAFFIC"
    }
  }
}

# Create a Network Endpoint Group for each Cloud Run service
resource "google_compute_region_network_endpoint_group" "serverless_endpoints" {
  count  = length(var.deployment_regions)
  name   = format("send-%s-%d", var.deployment_regions[count.index], count.index + 1)
  region = var.deployment_regions[count.index]

  cloud_run {
    service = google_cloud_run_v2_service.client[count.index].name
  }
}

# Create a backend service
resource "google_compute_backend_service" "serverless_service" {
  name                  = "serverless-service"
  protocol              = "HTTP"
  port_name             = "http"
  enable_cdn            = false
  load_balancing_scheme = "EXTERNAL_MANAGED"

  dynamic "backend" {
    for_each = google_compute_region_network_endpoint_group.serverless_endpoints
    content {
      group = backend.value.id
    }
  }
}

# Create a URL map
resource "google_compute_url_map" "url_map" {
  name            = "url-map"
  default_service = google_compute_backend_service.serverless_service.self_link
}

# Create an HTTP proxy
resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "http-proxy"
  url_map = google_compute_url_map.url_map.self_link
}

# Create a global forwarding rule
resource "google_compute_global_forwarding_rule" "forwarding_rule" {
  name                  = "forwarding-rule"
  target                = google_compute_target_http_proxy.http_proxy.self_link
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# Grant public access to each Cloud Run service
# resource "google_cloud_run_v2_service_iam_member" "public_access" {
#   count    = length(var.deployment_regions)
#   project  = var.gcp_project_id
#   location = var.deployment_regions[count.index]
#   name     = google_cloud_run_v2_service.client[count.index].name
#   role     = "roles/run.invoker"
#   member   = "allUsers"
# }

resource "google_cloud_run_v2_service_iam_binding" "binding" {
  count    = length(var.deployment_regions)
  project  = var.gcp_project_id
  location = var.deployment_regions[count.index]
  name     = google_cloud_run_v2_service.client[count.index].name
  role     = "roles/run.invoker"
  members = [
    "allUsers",
  ]
}