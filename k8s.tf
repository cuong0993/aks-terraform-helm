

resource "random_integer" "random_int" {
  min = 100
  max = 999
}

resource "azurerm_resource_group" "cluster" {
  name     = var.resource_group_name
  location = var.resource_group_location
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-${random_integer.random_int.result}"
  location            = azurerm_resource_group.cluster.location
  kubernetes_version  = var.kubernetes_version
  resource_group_name = azurerm_resource_group.cluster.name
  node_resource_group = "${azurerm_resource_group.cluster.name}-nodes"
  dns_prefix          = "aks-${random_integer.random_int.result}"

  default_node_pool {
    name                = "firstpool"
    min_count           = 1
    max_count           = 100
    vm_size             = var.vm_size
    max_pods            = 110
    enable_auto_scaling = true
    os_disk_size_gb     = 32
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
  }
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
  alias                  = "aks"
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
  }
}

resource "null_resource" "save-kube-config" {
  triggers = {
    config = azurerm_kubernetes_cluster.aks.kube_config_raw
  }
  provisioner "local-exec" {
    command = "echo '${azurerm_kubernetes_cluster.aks.kube_config_raw}' > ${path.module}/azure_config && chmod 0600 ${path.module}/azure_config"
  }
  depends_on = [azurerm_kubernetes_cluster.aks]
}

resource "kubernetes_namespace" "nginx_ingress" {
  metadata {
    name = "ingress-basic"
  }
  provider   = kubernetes.aks
  depends_on = [azurerm_kubernetes_cluster.aks]
}

resource "kubernetes_namespace" "wordpress" {
  metadata {
    name = "wordpress"
  }
  provider   = kubernetes.aks
  depends_on = [azurerm_kubernetes_cluster.aks]
}

resource "helm_release" "nginx_ingress" {
  name       = "nginx-ingress"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.6.1"
  wait       = false
  namespace  = kubernetes_namespace.nginx_ingress.metadata.0.name

  set {
    name  = "controller.replicaCount"
    value = "1"
  }
}

resource "helm_release" "wordpress" {
  name       = "wordpress"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "wordpress"
  version    = "22.4.10"
  wait       = false
  namespace  = kubernetes_namespace.wordpress.metadata.0.name

  set {
    name  = "persistence.storageClass"
    value = "default"
  }
  set {
    name  = "persistence.size"
    value = "5Gi"
  }
  set {
    name  = "livenessProbe.initialDelaySeconds"
    value = 1000
  }
  set {
    name  = "readinessProbe.initialDelaySeconds"
    value = 1000
  }
  set {
    name  = "ingress.enabled"
    value = "true"
  }
  set {
    name  = "service.type"
    value = "ClusterIP"
  }
}
