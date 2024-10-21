locals {
  aaa_name = lower("${var.company_trig}-${var.env}-${var.service_name}-AAA")
}

data azurerm_automation_account "cert_aa" {
  name                = local.aaa_name
  resource_group_name = data.azurerm_resource_group.certificates.name
}

