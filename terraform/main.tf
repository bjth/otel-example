provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
  }
}

# --- Azure Foundational Resources ---

resource "random_string" "cluster_suffix" {
  length  = 6
  special = false
  upper   = false
}

# Create Resource Group for AKS
resource "azurerm_resource_group" "aks_rg" {
  name     = var.aks_resource_group_name
  location = var.location
}

# Create AKS Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.aks_cluster_name_prefix}-${random_string.cluster_suffix.result}"
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
  dns_prefix          = "${var.aks_cluster_name_prefix}-${random_string.cluster_suffix.result}"
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name                       = var.node_pool_name
    vm_size                    = var.node_pool_vm_size
    node_count                 = var.enable_auto_scaling ? null : var.node_pool_min_count # Set fixed count if not autoscaling
    min_count                  = var.enable_auto_scaling ? var.node_pool_min_count : null
    max_count                  = var.enable_auto_scaling ? var.node_pool_max_count : null
    enable_auto_scaling        = var.enable_auto_scaling
    temporary_name_for_rotation = "temp${random_string.cluster_suffix.result}"
  }

  # Using SystemAssigned identity for simplicity
  # Consider UserAssigned for more granular control in production
  identity {
    type = "SystemAssigned"
  }

  # Enable Azure Blob CSI Driver Addon
  storage_profile {
    blob_driver_enabled = true
  }

  network_profile {
    network_plugin = "azure" # Or "kubenet"
    service_cidr   = "10.0.0.0/16"
    dns_service_ip = "10.0.0.10"
  }

  tags = {
    Environment = "Demo"
    Project     = "OpenTelemetrySample"
  }
}

# --- Azure Storage for Application Persistence ---

# Create Storage Account for Persistent Volumes
resource "azurerm_storage_account" "storage" {
  name                     = var.storage_account_name
  resource_group_name      = var.storage_account_resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Create Blob Container
resource "azurerm_storage_container" "container" {
  name                  = var.storage_container_name
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "private"

  # Ensure Storage Account exists before creating container
  depends_on = [azurerm_storage_account.storage]
}

# --- Kubernetes Namespace ---
resource "kubernetes_namespace" "ns" {
  metadata {
    name = var.kubernetes_namespace
  }
  # Ensure AKS cluster is ready before creating namespace
  depends_on = [azurerm_kubernetes_cluster.aks]
}

# --- Application Configuration Maps ---

resource "kubernetes_config_map" "mimir_config" {
  metadata {
    name      = "mimir-config"
    namespace = kubernetes_namespace.ns.metadata.0.name
  }
  data = {
    "mimir.yaml" = <<-EOT
      multitenancy_enabled: false
      server:
        http_listen_port: 9009
      blocks_storage:
        backend: filesystem
        filesystem:
          dir: /data/blocks
      distributor:
        ring:
          kvstore:
            store: inmemory
      ingester:
        ring:
          kvstore:
            store: inmemory
          replication_factor: 1
      ruler_storage:
        backend: filesystem
        filesystem:
          dir: /data/rules
      usage_stats:
        enabled: false
    EOT
  }
  depends_on = [kubernetes_namespace.ns]
}

resource "kubernetes_config_map" "tempo_config" {
  metadata {
    name      = "tempo-config"
    namespace = kubernetes_namespace.ns.metadata.0.name
  }
  data = {
    "tempo.yaml" = <<-EOT
      server:
        http_listen_port: 3200
      distributor:
        receivers:
          otlp:
            protocols:
              grpc:
                endpoint: "0.0.0.0:4317"
              http:
                endpoint: "0.0.0.0:4318"
      storage:
        trace:
          backend: local
          local:
            path: /tmp/tempo/blocks
      ingester:
        max_block_duration: 5m
        trace_idle_period: 10s
        flush_check_period: 1s
      compactor:
        compaction:
          block_retention: 24h
      metrics_generator:
        registry:
          external_labels:
            source: tempo
            cluster: aks
        storage:
          path: /tmp/tempo/generator/wal
          remote_write:
            # Use Kubernetes service DNS name
            - url: http://mimir.${kubernetes_namespace.ns.metadata.0.name}.svc.cluster.local:9009/api/v1/push
              send_exemplars: true
      overrides:
        metrics_generator_processors: [service-graphs, span-metrics]
      query_frontend:
        search:
          max_duration: 0
        max_outstanding_per_tenant: 100
        max_retries: 5
    EOT
  }
  depends_on = [kubernetes_namespace.ns]
}

resource "kubernetes_config_map" "otel_collector_config" {
  metadata {
    name      = "otel-collector-config"
    namespace = kubernetes_namespace.ns.metadata.0.name
  }
  data = {
    "otel-collector-config.yaml" = <<-EOT
      receivers:
        otlp:
          protocols:
            grpc:
              endpoint: 0.0.0.0:4317
              max_recv_msg_size_mib: 4
            http:
              endpoint: 0.0.0.0:4318
      processors:
        batch:
          timeout: 1s
          send_batch_size: 100
          send_batch_max_size: 100
        attributes:
          actions:
            - key: "loki.attribute.labels"
              action: "insert"
              value: "service.name,service.version,service.instance.id,severity_text"
        resource:
          attributes:
            - action: insert
              key: service.name
              value: "OpenTelemetryDemo.API" # Update if needed for AKS context
      exporters:
        otlphttp/mimir:
          # Use Kubernetes service DNS name
          endpoint: "http://mimir.${kubernetes_namespace.ns.metadata.0.name}.svc.cluster.local:9009/otlp"
          tls:
            insecure: true
          retry_on_failure:
            enabled: true
            initial_interval: 5s
            max_interval: 30s
            max_elapsed_time: 300s
        otlp/tempo:
          # Use Kubernetes service DNS name
          endpoint: tempo.${kubernetes_namespace.ns.metadata.0.name}.svc.cluster.local:4317
          tls:
            insecure: true
        otlphttp/loki:
          # Use Kubernetes service DNS name
          endpoint: "http://loki.${kubernetes_namespace.ns.metadata.0.name}.svc.cluster.local:3100/otlp"
          tls:
            insecure: true
          retry_on_failure:
            enabled: true
            initial_interval: 5s
            max_interval: 30s
            max_elapsed_time: 300s
      service:
        pipelines:
          traces:
            receivers: [otlp]
            processors: [batch]
            exporters: [otlp/tempo]
          metrics:
            receivers: [otlp]
            processors: [batch, resource]
            exporters: [otlphttp/mimir]
          logs:
            receivers: [otlp]
            processors: [batch, attributes]
            exporters: [otlphttp/loki]
    EOT
  }
  depends_on = [kubernetes_namespace.ns]
}

resource "kubernetes_config_map" "loki_config" {
  metadata {
    name      = "loki-config"
    namespace = kubernetes_namespace.ns.metadata.0.name
  }
  data = {
    "local-config.yaml" = <<-EOT
      auth_enabled: false
      server:
        http_listen_port: 3100
      common:
        path_prefix: /loki # Mount path for PVC
        storage:
          filesystem:
            chunks_directory: /loki/chunks
            rules_directory: /loki/rules
        replication_factor: 1
        ring:
          kvstore:
            store: inmemory

      # Use schema v13 with tsdb index to support structured metadata
      schema_config:
        configs:
          - from: 2022-01-11 # Date v13 schema became available
            store: tsdb
            object_store: filesystem
            schema: v13
            index:
              prefix: index_
              period: 24h

      storage_config: # storage_config is needed when using tsdb store
        filesystem:
          directory: /loki/tsdb # Directory for the TSDB index files

      compactor:
        working_directory: /loki/compactor
        compaction_interval: 5m

      limits_config:
        reject_old_samples: true
        reject_old_samples_max_age: 168h
        # Re-enable structured metadata
        allow_structured_metadata: true
    EOT
  }
  depends_on = [kubernetes_namespace.ns]
}

resource "kubernetes_config_map" "grafana_datasources" {
  metadata {
    name      = "grafana-datasources"
    namespace = kubernetes_namespace.ns.metadata.0.name
  }
  data = {
    "datasources.yaml" = <<-EOT
      apiVersion: 1
      datasources:
        - name: Mimir
          type: prometheus
          access: proxy
          # Use Kubernetes service DNS name
          url: http://mimir.${kubernetes_namespace.ns.metadata.0.name}.svc.cluster.local:9009/prometheus
          isDefault: true
          jsonData:
            httpMethod: GET
            prometheusType: Mimir
            prometheusVersion: "2.9.1" # Check compatibility if needed
            timeInterval: "15s"
            exemplarTraceIdDestinations:
              - name: traceID
                datasourceUid: tempo # Assuming tempo datasource UID remains 'tempo'

        - name: Loki
          type: loki
          access: proxy
          # Use Kubernetes service DNS name
          url: http://loki.${kubernetes_namespace.ns.metadata.0.name}.svc.cluster.local:3100
          isDefault: false

        - name: Tempo
          uid: tempo # Define UID for reference
          type: tempo
          access: proxy
          # Use Kubernetes service DNS name
          url: http://tempo.${kubernetes_namespace.ns.metadata.0.name}.svc.cluster.local:3200
          isDefault: false
    EOT
  }
  depends_on = [kubernetes_namespace.ns]
}

# --- Persistent Volume Claims using Azure Blob ---

resource "kubernetes_persistent_volume_claim" "mimir_pvc" {
  metadata {
    name      = "mimir-data"
    namespace = kubernetes_namespace.ns.metadata.0.name
  }
  spec {
    access_modes       = ["ReadWriteOnce"] # Blob fuse supports RWO
    storage_class_name = "azureblob-fuse-premium" # Use the Storage Class created by the AKS addon
    resources {
      requests = {
        storage = "10Gi" # Adjust size as needed
      }
    }
  }
  depends_on = [kubernetes_namespace.ns, azurerm_kubernetes_cluster.aks] # Ensure namespace exists and CSI driver is ready
}

resource "kubernetes_persistent_volume_claim" "tempo_pvc" {
  metadata {
    name      = "tempo-data"
    namespace = kubernetes_namespace.ns.metadata.0.name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "azureblob-fuse-premium" # Use the Storage Class created by the AKS addon
    resources {
      requests = {
        storage = "10Gi" # Adjust size as needed
      }
    }
  }
  depends_on = [kubernetes_namespace.ns, azurerm_kubernetes_cluster.aks]
}

resource "kubernetes_persistent_volume_claim" "loki_pvc" {
  metadata {
    name      = "loki-data"
    namespace = kubernetes_namespace.ns.metadata.0.name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "azureblob-fuse-premium" # Use the Storage Class created by the AKS addon
    resources {
      requests = {
        storage = "10Gi" # Adjust size as needed
      }
    }
  }
  depends_on = [kubernetes_namespace.ns, azurerm_kubernetes_cluster.aks]
}

resource "kubernetes_persistent_volume_claim" "grafana_pvc" {
  metadata {
    name      = "grafana-data"
    namespace = kubernetes_namespace.ns.metadata.0.name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "azureblob-fuse-premium" # Use the Storage Class created by the AKS addon
    resources {
      requests = {
        storage = "2Gi" # Adjust size as needed
      }
    }
  }
  depends_on = [kubernetes_namespace.ns, azurerm_kubernetes_cluster.aks]
}

# --- Kubernetes Deployments ---

resource "kubernetes_deployment" "mimir" {
  metadata {
    name      = "mimir"
    namespace = kubernetes_namespace.ns.metadata.0.name
    labels = {
      app = "mimir"
    }
  }
  spec {
    replicas = 1 # Adjust for HA if needed
    selector {
      match_labels = {
        app = "mimir"
      }
    }
    template {
      metadata {
        labels = {
          app = "mimir"
        }
      }
      spec {
        container {
          name  = "mimir"
          image = "grafana/mimir:latest"
          args  = ["-config.file=/etc/mimir/mimir.yaml"]
          port {
            container_port = 9009
          }
          volume_mount {
            name       = "config"
            mount_path = "/etc/mimir"
          }
          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.mimir_config.metadata.0.name
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.mimir_pvc.metadata.0.name
          }
        }
      }
    }
  }
  depends_on = [kubernetes_persistent_volume_claim.mimir_pvc]
}

resource "kubernetes_deployment" "tempo" {
  metadata {
    name      = "tempo"
    namespace = kubernetes_namespace.ns.metadata.0.name
    labels = {
      app = "tempo"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "tempo"
      }
    }
    template {
      metadata {
        labels = {
          app = "tempo"
        }
      }
      spec {
        # user: root - Not recommended in K8s, check if image requires it or if fsGroup/runAsUser can be used
        security_context {
          run_as_user  = 0 # Equivalent to user: root, use with caution
          run_as_group = 0
          fs_group     = 0 # May be needed for volume permissions
        }
        container {
          name  = "tempo"
          image = "grafana/tempo:latest"
          args  = ["-config.file=/etc/tempo.yaml"]
          port {
            name           = "http-query"
            container_port = 3200
          }
          port {
            name           = "otlp-grpc"
            container_port = 4317
          }
          port {
            name           = "otlp-http"
            container_port = 4318
          }
          volume_mount {
            name       = "config"
            mount_path = "/etc/tempo.yaml"
            sub_path   = "tempo.yaml"
          }
          volume_mount {
            name       = "data"
            mount_path = "/tmp/tempo"
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.tempo_config.metadata.0.name
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.tempo_pvc.metadata.0.name
          }
        }
      }
    }
  }
  depends_on = [kubernetes_persistent_volume_claim.tempo_pvc]
}

resource "kubernetes_deployment" "otel_collector" {
  metadata {
    name      = "otel-collector"
    namespace = kubernetes_namespace.ns.metadata.0.name
    labels = {
      app = "otel-collector"
    }
  }
  spec {
    replicas = 1 # Adjust as needed
    selector {
      match_labels = {
        app = "otel-collector"
      }
    }
    template {
      metadata {
        labels = {
          app = "otel-collector"
        }
      }
      spec {
        container {
          name  = "otel-collector"
          image = "otel/opentelemetry-collector:latest"
          args  = ["--config=/etc/otel-collector-config.yaml"]
          port {
            name           = "otlp-grpc"
            container_port = 4317
          }
          port {
            name           = "otlp-http"
            container_port = 4318
          }
          # 4319 defined in docker-compose but not used in config, omitting for now
          volume_mount {
            name       = "config"
            mount_path = "/etc/otel-collector-config.yaml"
            sub_path   = "otel-collector-config.yaml"
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.otel_collector_config.metadata.0.name
          }
        }
      }
    }
  }
  depends_on = [kubernetes_config_map.otel_collector_config]
}

resource "kubernetes_deployment" "loki" {
  metadata {
    name      = "loki"
    namespace = kubernetes_namespace.ns.metadata.0.name
    labels = {
      app = "loki"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "loki"
      }
    }
    template {
      metadata {
        labels = {
          app = "loki"
        }
      }
      spec {
        container {
          name  = "loki"
          image = "grafana/loki:latest"
          args  = ["-config.file=/etc/loki/local-config.yaml"]
          port {
            name           = "http"
            container_port = 3100
          }
          port {
            name           = "otlp-grpc"
            container_port = 4317
          }
          port {
            name           = "otlp-http"
            container_port = 4318
          }
          volume_mount {
            name       = "config"
            mount_path = "/etc/loki"
          }
          volume_mount {
            name       = "data"
            mount_path = "/loki"
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.loki_config.metadata.0.name
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.loki_pvc.metadata.0.name
          }
        }
      }
    }
  }
  depends_on = [kubernetes_persistent_volume_claim.loki_pvc]
}

resource "kubernetes_deployment" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.ns.metadata.0.name
    labels = {
      app = "grafana"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "grafana"
      }
    }
    template {
      metadata {
        labels = {
          app = "grafana"
        }
      }
      spec {
        # Grafana typically needs write permissions to /var/lib/grafana
        security_context {
          run_as_user = 472 # Grafana user ID
          fs_group    = 472 # Grafana group ID
        }
        container {
          name  = "grafana"
          image = "grafana/grafana:latest"
          port {
            container_port = 3000
          }
          # Env var removed - Grafana is now accessed at the root of port 3000
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/grafana"
          }
          volume_mount {
            name       = "provisioning-datasources"
            mount_path = "/etc/grafana/provisioning/datasources"
            read_only  = true
          }
          # Add other provisioning mounts if needed (e.g., dashboards)
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.grafana_pvc.metadata.0.name
          }
        }
        volume {
          name = "provisioning-datasources"
          config_map {
            name = kubernetes_config_map.grafana_datasources.metadata.0.name
          }
        }
      }
    }
  }
  depends_on = [kubernetes_persistent_volume_claim.grafana_pvc]
}

# --- Kubernetes Services ---

resource "kubernetes_service" "mimir" {
  metadata {
    name      = "mimir"
    namespace = kubernetes_namespace.ns.metadata.0.name
  }
  spec {
    selector = {
      app = kubernetes_deployment.mimir.spec.0.template.0.metadata.0.labels.app
    }
    port {
      name        = "http"
      port        = 9009
      target_port = 9009
    }
    type = "ClusterIP"
  }
  depends_on = [kubernetes_deployment.mimir]
}

resource "kubernetes_service" "tempo" {
  metadata {
    name      = "tempo"
    namespace = kubernetes_namespace.ns.metadata.0.name
  }
  spec {
    selector = {
      app = kubernetes_deployment.tempo.spec.0.template.0.metadata.0.labels.app
    }
    port {
      name        = "http-query"
      port        = 3200
      target_port = "http-query"
    }
    port {
      name        = "otlp-grpc"
      port        = 4317
      target_port = "otlp-grpc"
      app_protocol = "grpc"
    }
    port {
      name        = "otlp-http"
      port        = 4318
      target_port = "otlp-http"
    }
    type = "ClusterIP"
  }
  depends_on = [kubernetes_deployment.tempo]
}

resource "kubernetes_service" "otel_collector" {
  metadata {
    name      = "otel-collector"
    namespace = kubernetes_namespace.ns.metadata.0.name
  }
  spec {
    selector = {
      app = kubernetes_deployment.otel_collector.spec.0.template.0.metadata.0.labels.app
    }
    port {
      name        = "otlp-grpc"
      port        = 4317
      target_port = "otlp-grpc"
      app_protocol = "grpc"
    }
    port {
      name        = "otlp-http"
      port        = 4318
      target_port = "otlp-http"
    }
    type = "ClusterIP"
  }
  depends_on = [kubernetes_deployment.otel_collector]
}

resource "kubernetes_service" "loki" {
  metadata {
    name      = "loki"
    namespace = kubernetes_namespace.ns.metadata.0.name
  }
  spec {
    selector = {
      app = kubernetes_deployment.loki.spec.0.template.0.metadata.0.labels.app
    }
    port {
      name        = "http"
      port        = 3100
      target_port = "http"
    }
    type = "ClusterIP"
  }
  depends_on = [kubernetes_deployment.loki]
}

resource "kubernetes_service" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.ns.metadata.0.name
  }
  spec {
    selector = {
      app = kubernetes_deployment.grafana.spec.0.template.0.metadata.0.labels.app
    }
    port {
      name        = "http"
      port        = 3000
      target_port = 3000
    }
    type = "ClusterIP"
  }
  depends_on = [kubernetes_deployment.grafana]
}

# --- NGINX Ingress Controller Installation (using Helm) ---
resource "helm_release" "nginx_ingress" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = kubernetes_namespace.ns.metadata.0.name
  version    = var.nginx_ingress_chart_version
  create_namespace = false # Namespace is created above

  # --- Helm Values Configuration ---
  values = [
    <<-EOT
    controller:
      replicaCount: 2 # Adjust based on expected load
      admissionWebhooks:
        enabled: false # Simplifies setup, enable if needed for stricter validation
      publishService:
        enabled: true
      service:
        annotations:
          # Required for Azure Load Balancer health probes
          service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path: /healthz
        # Expose necessary ports directly on the LoadBalancer
        ports:
          http: 80       # Still needed for potential future HTTP ingresses or health checks
          https: 443      # Still needed for potential future HTTPS ingresses
          otel-grpc: 4317 # External port for OTel gRPC
          otel-http: 4318 # External port for OTel HTTP
          grafana: 3000   # External port for Grafana

    # TCP ConfigMap setup should be at the root level
    tcp:
      # Map external port 4317 to OTel Collector gRPC service:port
      "4317": "${kubernetes_namespace.ns.metadata.0.name}/${kubernetes_service.otel_collector.metadata.0.name}:4317"
      # Map external port 4318 to OTel Collector HTTP service:port
      "4318": "${kubernetes_namespace.ns.metadata.0.name}/${kubernetes_service.otel_collector.metadata.0.name}:4318"
      # Map external port 3000 to Grafana service:port
      "3000": "${kubernetes_namespace.ns.metadata.0.name}/${kubernetes_service.grafana.metadata.0.name}:3000"

    EOT
  ]

  depends_on = [
     kubernetes_namespace.ns,
     kubernetes_service.otel_collector, # Needed for TCP mapping
     kubernetes_service.grafana         # Needed for TCP mapping
   ]
}

# Data source to get the LoadBalancer IP of the Ingress controller
data "kubernetes_service" "nginx_ingress_service" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = helm_release.nginx_ingress.namespace
  }
  depends_on = [helm_release.nginx_ingress]
}

# Get the LoadBalancer IP (handle potential delays)
locals {
  nginx_lb_ip = try(data.kubernetes_service.nginx_ingress_service.status.0.load_balancer.0.ingress.0.ip, null)
}

# --- Outputs ---
output "otel_http_endpoint" {
  description = "Endpoint for the OpenTelemetry Collector HTTP endpoint (OTLP/HTTP)"
  value       = local.nginx_lb_ip == null ? "(Waiting for Ingress IP...)" : "http://${local.nginx_lb_ip}:4318"
}

output "otel_grpc_endpoint" {
  description = "Endpoint for the OpenTelemetry Collector gRPC endpoint (OTLP/gRPC)"
  value       = local.nginx_lb_ip == null ? "(Waiting for Ingress IP...)" : "${local.nginx_lb_ip}:4317"
}

output "grafana_endpoint" {
  description = "URL for the Grafana dashboard"
  value       = local.nginx_lb_ip == null ? "(Waiting for Ingress IP...)" : "http://${local.nginx_lb_ip}:3000"
}

output "nginx_loadbalancer_ip" {
  description = "Public IP address of the NGINX Ingress Load Balancer"
  value       = local.nginx_lb_ip == null ? "(Waiting for Ingress IP...)" : local.nginx_lb_ip
} 