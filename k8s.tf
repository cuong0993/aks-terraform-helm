resource "random_string" "aks_sp_password" {
    length  = 16
    special = true
    keepers = {
        service_principal = azuread_service_principal.auth.id
    }
}

resource "random_integer" "random_int" {
    min = 100
    max = 999
}

resource "azuread_application" "auth" {
    name = "${var.sp_name}-${var.resource_group_name}-${var.resource_group_location}"
}

resource "azuread_service_principal" "auth" {
    application_id = azuread_application.auth.application_id
}

resource "azuread_service_principal_password" "auth" {
    service_principal_id = azuread_service_principal.auth.id
    value                = random_string.aks_sp_password.result
    end_date_relative    = "43800h" # 5 years

    # needed for the service principal and application sync inside Azure
    # https://github.com/terraform-providers/terraform-provider-azuread/issues/4#issuecomment-407542721

    provisioner "local-exec" {
        command = "sleep 60"
    }
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
        name       = "firstpool"
        min_count  = 1
        max_count  = 100
        vm_size    = var.vm_size
        max_pods   = 110
        enable_auto_scaling = true
        os_disk_size_gb     = 32
    }

    service_principal {
        client_id     = azuread_service_principal.auth.application_id
        client_secret = azuread_service_principal_password.auth.value
    }

    network_profile {
        network_plugin = "azure"
    }
}

# forcing 1.10.0 here because of a bug\by design in 1.11.0
# https://github.com/terraform-providers/terraform-provider-kubernetes/issues/759
provider "kubernetes" {
    host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
    alias                  = "aks"
    version                = "1.10.0"
    load_config_file       = "false"
}

provider "helm" {
    kubernetes {
        host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
        client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
        client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
        cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
    }
}

data "helm_repository" "stable" {
    name = "stable"
    url  = "https://kubernetes-charts.storage.googleapis.com"
}

data "helm_repository" "bitnami" {
    name = "bitnami"
    url  = "https://charts.bitnami.com/bitnami"
}

resource "null_resource" "save-kube-config" {
    triggers = {
        config = azurerm_kubernetes_cluster.aks.kube_config_raw
    }
    provisioner "local-exec" {
        command = "echo '${azurerm_kubernetes_cluster.aks.kube_config_raw}' > ${path.module}/azure_config && chmod 0600 ${path.module}/azure_config"
    }
    depends_on = [ azurerm_kubernetes_cluster.aks ]
}

resource "kubernetes_namespace" "nginx_ingress" {
    metadata {
        name = "ingress-basic"
    } 
    provider = kubernetes.aks
    depends_on = [ azurerm_kubernetes_cluster.aks ]
}

resource "kubernetes_namespace" "wordpress" {
    metadata {
        name = "wordpress"
    } 
    provider = kubernetes.aks
    depends_on = [ azurerm_kubernetes_cluster.aks ]
}

resource "helm_release" "nginx_ingress" {
    name       = "nginx-ingress"
    repository = data.helm_repository.stable.metadata.0.name
    chart      = "nginx-ingress"
    wait       = false
    namespace  = kubernetes_namespace.nginx_ingress.metadata.0.name

    set {
        name  = "controller.replicaCount"
        value = "1"
    }
}

resource "helm_release" "wordpress" {
    name       = "wordpress"
    repository = data.helm_repository.bitnami.metadata.0.name
    chart      = "wordpress"
    wait       = false
    namespace  = kubernetes_namespace.wordpress.metadata.0.name

    set_string {
        name  = "persistence.storageClass"
        value = "default"
    }
    set_string {
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
    set_string {
        name  = "service.type"
        value = "ClusterIP"
    }
}