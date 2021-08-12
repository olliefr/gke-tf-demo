terraform {
  required_version = ">= 0.15"
}

provider "google" {
	project = var.project
	region  = var.region
	zone    = var.zone
}

resource "google_project_service" "compute" {
  service = "compute.googleapis.com"
}

resource "google_project_service" "container" {
  service = "container.googleapis.com"
}

resource "google_compute_network" "gke" {
  name                    = "gkenet"
  auto_create_subnetworks = false
}

# TODO make node, pod, services IP ranges variables

resource "google_compute_subnetwork" "prod" {
  network       = google_compute_network.gke.id
  name          = "prod"
  ip_cidr_range = "10.0.0.0/16"
  
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pod-ranges"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services-range"
    ip_cidr_range = "10.2.0.0/16"
  }
}

resource "google_container_cluster" "prod" {
  location                 = var.region
  name                     = "prod"
  initial_node_count       = 1
  remove_default_node_pool = true

  network    = google_compute_network.gke.id
  subnetwork = google_compute_subnetwork.prod.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "services-range"
    services_secondary_range_name = "pod-ranges"
  }

  # TODO private endpoint
  # TODO variable for master_ipv4_cidr_block

  private_cluster_config {
    enable_private_nodes    = true
    master_ipv4_cidr_block  = "172.16.0.0/28"
    enable_private_endpoint = false

    master_global_access_config {
      enabled = false
    }
  }

  # TODO update to support multiple authorised networks
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = var.authorized_networks[0].cidr_block
      display_name = var.authorized_networks[0].display_name
    }
  }
}

resource "google_container_node_pool" "e2_medium_pool" {
	cluster            = google_container_cluster.prod.name
	location           = google_container_cluster.prod.location
	name               = "e2-medium-pool"
  
  # In regional or multi-zonal clusters, number of nodes per zone
  node_count         = 1

  node_config {
    preemptible  = var.preemptible
    machine_type = "e2-medium"
    image_type   = "COS_CONTAINERD"
		disk_size_gb = "12"

    # TODO limited service_accounts for instances
  }
}