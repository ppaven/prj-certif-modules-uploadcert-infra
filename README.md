# Create-certif terraform module
# Create and execute a webhook which call the Runbook "CreateCert-LetsEncrypt".

[![pipeline status]]

## description

Module to create a letsencrypt certificate and install it in the resource or in a local keyvault.

## vars

- Required:
  - **aaa_subs_id** => Subscription ID of Automation Account
  - **aaa_rgp** => Resource group name of Automation Account
  - **aaa_name** => Automation Account name
  - **domain_names** => List of domain names separate by a comma
  - **dns_subscription** => Subscription Name of the DNS zone
  - **dns_resource_group** => Resource group name of the DNS zone
  - **dns_zone** => Name of the DNS zone
  - **subscription** => Subscription name of the resources
  - **resource_group** => Resource group name of the resources
  - **resource_type** => Resource type of the resources (AppService, API, AGW, VM, VMG)
  - **resources** => List of resources separate by a comma
  
- Optional:
  - **endpoint_listener** => API : Endpoint name. AGW : listener name
  - **keyvault** => local keyvault to store the certificate  
  - **test** => Letencrypt Staging mode or not (Default = false)
- 
## outputs


## usage

```
module "certificate_test" {
  source              = "../modules/create-certif/"

  aaa_subs_id         = "AZC-SUB-HUB"
  aaa_rgp             = "AZC-POC-RG-CERT"
  aaa_name            = "azc-poc-cert-aaa"
  domain_names        = "test.azcloud-consulting.com"
  dns_subscription    = "AZC-SUB-HUB"
  dns_resource_group  = "AZCH-RG-DNS"
  dns_zone            = "azcloud-consulting.com"
  subscription        = "AZC-SUB-POC"
  resource_group      = "AZCP-RG-TST"
  resource_type       = "AppService"
  resources           = "azcptestapp001"
  keyvault            = "AZCP-TEST-KVT01"
  test                = true
}
```
