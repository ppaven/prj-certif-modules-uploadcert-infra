data template_file "runbook_upload" {
  template = file("${path.module}/runbooks/${var.runbook_upload}.tpl.ps1")
  vars = {
    vault = local.keyvault_name
    subscription = data.azurerm_subscription.subs.display_name
    automationId = data.azurerm_automation_account.cert_aa.identity[0].principal_id
  } 
}

resource azurerm_automation_runbook "runbook_upload" {
  name                = var.runbook_upload
  location            = data.azurerm_resource_group.certificates.location
  resource_group_name = data.azurerm_resource_group.certificates.name
  automation_account_name = data.azurerm_automation_account.cert_aa.name
  log_verbose         = "false"
  log_progress        = "false"
  description         = "Runbook to upload certificate in resources"
  runbook_type        = "PowerShell72"

  publish_content_link {
    uri = "https://raw.githubusercontent.com/Azure/azure-quickstart-templates/c4935ffb69246a6058eb24f54640f53f69d3ac9f/101-automation-runbook-getvms/Runbooks/Get-AzureVMTutorial.ps1"
  }

  content = data.template_file.runbook_upload.rendered

  tags = var.tags 
}
