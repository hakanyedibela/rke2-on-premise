
resource "null_resource" "install_kafka_operator" {
  depends_on = [null_resource.get_kubeconfig]

  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG=${path.module}/kubeconfig.yaml
      kubectl create namespace kafka --dry-run=client -o yaml | kubectl apply -f -
      kubectl create -f 'https://strimzi.io/install/latest?namespace=kafka' -n kafka
      kubectl wait --for=condition=ready pod -l name=strimzi-cluster-operator -n kafka --timeout=300s
    EOT
  }

  triggers = {
    kubeconfig = filemd5("${path.module}/kubeconfig.yaml")
  }
}

resource "null_resource" "deploy_kafka_cluster" {
  depends_on = [null_resource.install_kafka_operator]

  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG=${path.module}/kubeconfig.yaml
      kubectl apply -f ${path.module}/kafka-cluster.yaml -n kafka
      echo "Waiting for Kafka cluster to be ready..."
      kubectl wait kafka/hkndev-cluster --for=condition=Ready --timeout=600s -n kafka
    EOT
  }

  triggers = {
    kafka_config = filemd5("${path.module}/kafka-cluster.yaml")
  }
}
