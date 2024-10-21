
################
# Variables for naming convention

#---------
# Compagny trigram
variable company_trig {
  default = "AZC"
}
#---------
# Environment
variable env {
    default = "POC"
}

#---------
# Short Service/Project name 
variable service_name {
  type        = string
  default  = "CERT"
}

################
# Souscription
variable subscription_id {} # = Environment variable TF_VAR_subscription_id

################
# Location
variable location {
  default = "francecentral"
}

################
# Runbooks

variable runbook_upload {
  default = "UploadCertToResources"
}

################
# Tags

variable tags {
    type        = map(string)
}
