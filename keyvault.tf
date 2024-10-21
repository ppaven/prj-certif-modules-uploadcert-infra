locals {
  keyvault_name = "${var.company_trig}-${var.env}-${var.service_name}-KVT01"
}

data azurerm_key_vault "cert_vault" {
  name                = local.keyvault_name
  resource_group_name = data.azurerm_resource_group.certificates.name
}
################
# Add update_cert.sh script to keyvault 

resource "azurerm_key_vault_secret" "updatecert" {
    name  = "UpdateCert"
    value = base64encode(file("${path.module}/scripts/update_cert.sh"))
    key_vault_id = data.azurerm_key_vault.cert_vault.id
}