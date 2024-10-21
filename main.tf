provider azurerm {
  subscription_id = var.subscription_id
  # resource_provider_registrations = "core"
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}

data azurerm_client_config "current" {}

data "azurerm_subscription" "subs" {
  subscription_id = var.subscription_id
}

locals {
    resource_group_name = "${var.company_trig}-${var.env}-RG-${var.service_name}"
}

data azurerm_resource_group "certificates" {
  name     = local.resource_group_name
}
