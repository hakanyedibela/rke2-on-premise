
# ----------------------------------------------------------
# Cassandra Namespace
# ----------------------------------------------------------
resource "kubernetes_namespace" "cassandra" {
  metadata {
    name = "cassandra"
  }

  depends_on = [null_resource.get_kubeconfig]
}

# ----------------------------------------------------------
# Cassandra Headless Service
# ----------------------------------------------------------
resource "kubernetes_service" "cassandra" {
  metadata {
    name      = "cassandra"
    namespace = kubernetes_namespace.cassandra.metadata[0].name
    labels = {
      app = "cassandra"
    }
  }

  spec {
    cluster_ip = "None"

    port {
      port        = 9042
      target_port = 9042
      name        = "cql"
    }

    port {
      port        = 7000
      target_port = 7000
      name        = "intra-node"
    }

    port {
      port        = 7001
      target_port = 7001
      name        = "tls-intra-node"
    }

    port {
      port        = 7199
      target_port = 7199
      name        = "jmx"
    }

    selector = {
      app = "cassandra"
    }
  }

  depends_on = [kubernetes_namespace.cassandra]
}

# ----------------------------------------------------------
# Cassandra StorageClass
# ----------------------------------------------------------
resource "kubernetes_storage_class" "cassandra" {
  metadata {
    name = "cassandra-storage"
  }

  storage_provisioner = "rancher.io/local-path"
  reclaim_policy      = "Retain"
  volume_binding_mode = "WaitForFirstConsumer"

  depends_on = [null_resource.get_kubeconfig]
}

# ----------------------------------------------------------
# Cassandra StatefulSet
# ----------------------------------------------------------
resource "kubernetes_stateful_set" "cassandra" {
  metadata {
    name      = "cassandra"
    namespace = kubernetes_namespace.cassandra.metadata[0].name
    labels = {
      app = "cassandra"
    }
  }

  spec {
    service_name = kubernetes_service.cassandra.metadata[0].name
    replicas     = 1  # Single node for 4GB RAM

    selector {
      match_labels = {
        app = "cassandra"
      }
    }

    template {
      metadata {
        labels = {
          app = "cassandra"
        }
      }

      spec {
        container {
          name  = "cassandra"
          image = "cassandra:4.1"

          port {
            container_port = 9042
            name           = "cql"
          }

          port {
            container_port = 7000
            name           = "intra-node"
          }

          port {
            container_port = 7001
            name           = "tls-intra-node"
          }

          port {
            container_port = 7199
            name           = "jmx"
          }

          # Resource limits for 4GB RAM system
          resources {
            requests = {
              memory = "768Mi"
              cpu    = "500m"
            }
            limits = {
              memory = "1536Mi"
              cpu    = "1000m"
            }
          }

          # Environment variables
          env {
            name  = "CASSANDRA_CLUSTER_NAME"
            value = "HKNDev Cluster"
          }

          env {
            name  = "CASSANDRA_DC"
            value = "DC1"
          }

          env {
            name  = "CASSANDRA_RACK"
            value = "Rack1"
          }

          env {
            name  = "CASSANDRA_ENDPOINT_SNITCH"
            value = "GossipingPropertyFileSnitch"
          }

          env {
            name  = "MAX_HEAP_SIZE"
            value = "512M"
          }

          env {
            name  = "HEAP_NEWSIZE"
            value = "128M"
          }

          env {
            name = "POD_IP"
            value_from {
              field_ref {
                field_path = "status.podIP"
              }
            }
          }

          # Readiness probe
          readiness_probe {
            exec {
              command = ["/bin/bash", "-c", "nodetool status"]
            }
            initial_delay_seconds = 90
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          # Liveness probe
          liveness_probe {
            exec {
              command = ["/bin/bash", "-c", "nodetool status"]
            }
            initial_delay_seconds = 120
            period_seconds        = 30
            timeout_seconds       = 10
            failure_threshold     = 3
          }

          # Volume mount
          volume_mount {
            name       = "cassandra-data"
            mount_path = "/var/lib/cassandra"
          }
        }

        # Termination grace period
        termination_grace_period_seconds = 30
      }
    }

    # Volume claim template
    volume_claim_template {
      metadata {
        name = "cassandra-data"
      }

      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = kubernetes_storage_class.cassandra.metadata[0].name

        resources {
          requests = {
            storage = "10Gi"
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_service.cassandra,
    kubernetes_storage_class.cassandra
  ]
}

# ----------------------------------------------------------
# Cassandra ConfigMap for Initialization
# ----------------------------------------------------------
resource "kubernetes_config_map" "cassandra_init" {
  metadata {
    name      = "cassandra-init"
    namespace = kubernetes_namespace.cassandra.metadata[0].name
  }

  data = {
    "init.cql" = <<-EOT
      CREATE KEYSPACE IF NOT EXISTS hkndev
      WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};

      USE hkndev;

      CREATE TABLE IF NOT EXISTS users (
        id UUID PRIMARY KEY,
        username TEXT,
        email TEXT,
        created_at TIMESTAMP
      );

      CREATE TABLE IF
    EOT
  }

  depends_on = [kubernetes_namespace.cassandra]
}
