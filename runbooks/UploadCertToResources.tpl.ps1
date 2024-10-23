#requires -Modules Az, Az.Websites, Az.Dns, Az.Keyvault

<#PSScriptInfo
.VERSION 0.1
.TITLE Create Cert - LetsEncrypt
.AUTHOR 
.GUID 
.DESCRIPTION 
.MANUAL 
.TAGS LetsEncrypt SSL Azure
#>
param(

    [Parameter(Mandatory)]
    [String] $CertificateName,

    [Parameter(Mandatory)]
    [String] $DomainName,

    [Parameter(Mandatory)]
    [String] $SubscriptionNameAll,

    [Parameter(Mandatory)]
    [String] $ResourceGroupAll,

    [Parameter(Mandatory)]
    [String] $ResourceTypeAll,

    [Parameter(Mandatory)]
    [String] $ResourcesAll,

    [Parameter(Mandatory=$false)]
    [String] $EndPoint_ListenerAll,

    [Parameter(Mandatory=$false)]
    [String] $KeyVaultAll

)

Set-StrictMode -Version Latest
########################
# Initialize Variables
########################
$VaultName = "${vault}"
$VaultSubscription = "${subscription}"
$AutomationId = "${automationId}"
$UpdateCertSecret = "UpdateCert"
$UpdateCertName = "update_cert.sh"
$ErrorJob = 0
$ErrorActionPreference = ‘Stop’

##  Connect to Azure
###############################################################################################
"Logging in to Azure..."

function RunWithManagedIdentity {
    try
    {
        Connect-AzAccount -Identity
    }
    catch {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

# RunAs Account is deprecated => RunWithManagedIdentity
RunWithManagedIdentity
$AzureContext = Get-AzContext

$vaultCtx = Set-AzContext -Subscription $VaultSubscription

###############################################################################################
## Export du certificat au format PFX
###############################################################################################
# Récupération du certificat dans le keyvault letsencrypt

$rawPassword =  -join (([int][char]'a'..[int][char]'z') | Get-Random -Count 20 | % { [char] $_ })
$securePassword = ConvertTo-SecureString $rawPassword -AsPlainText -Force

$secretValueText = Get-AzKeyVaultSecret -VaultName $VaultName -Name $CertificateName -AsPlainText
if (! $secretValueText) {
    Write-Error -Message "Secret Certificate not found"
    throw "Secret Certificate not found"
}

# Conversion et génération du pfx
$certBytes = [Convert]::FromBase64String($secretValueText)
$pfxPath = Join-Path $pwd export-cert.pfx

$x509Cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certBytes, "", "Exportable,PersistKeySet")
$type = [System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx
$pfxFileByte = $x509Cert.Export($type, $securePassword);
[System.IO.File]::WriteAllBytes($pfxPath, $pfxFileByte)
    
$CertLets = Get-AzKeyVaultCertificate -VaultName $VaultName -Name $CertificateName

if (! $CertLets) {
    Write-Error -Message "Certificate not found"
    throw "Certificate not found"
}
$ThumbLets = $CertLets.Thumbprint    
$CertTags = $CertLets.Tags

###############################################################################################
## Installation du certificat dans les ressources Azure
###############################################################################################
$ipos = 0
$ResourceTypeAll.Split("|") | ForEach {
    $ResourceType = $ResourceTypeAll.Split("|")[$ipos]
    $Resources = $ResourcesAll.Split("|")[$ipos]
    $SubscriptionName = $SubscriptionNameAll.Split("|")[$ipos]
    $ResourceGroupName = $ResourceGroupAll.Split("|")[$ipos]
    $EndPoint_Listener = $EndPoint_ListenerAll.Split("|")[$ipos]
    $KeyVault = $KeyVaultAll.Split("|")[$ipos]

    $ResourceCtx = Set-AzContext -Subscription "$SubscriptionName"

    Switch ($ResourceType) {
        "AppService" {
            if ($KeyVault -ne "") {
                "App Service - Upload Certificate to keyvault ..."
                $null = Import-AzKeyVaultCertificate -VaultName $KeyVault -Name $CertificateName -FilePath $pfxPath -Password $securePassword
            } 
            else {
                "App Service - Upload Certificate ..."
                try {
                    New-AzWebAppSSLBinding -ResourceGroupName $ResourceGroupName -WebAppName $Resources -Name $DomainName -CertificateFilePath $pfxPath -CertificatePassword $rawPassword -SslState SniEnabled
                }
                catch {
                    Write-Error "Error on uploading Certificate to AppService !"
                    $ErrorJob++
                } 
            }
        }
        "API" {
            "API : Upload Certificate to keyvault ..."
            if ($KeyVault -ne "") {
                $pos=$KeyVault.IndexOf("/")
                if ($pos -ne -1) {
                    $KeyVaultName=$KeyVault.Substring(0,$pos)
                    $KeyVaultSecret=$KeyVault.Substring($pos+1,$KeyVault.Length-$pos-1)
                } 
                else {
                    $KeyVaultName = $KeyVault
                    $KeyVaultSecret = $CertificateName
                }
                $UploadCert = $false
                $CertAPI = Get-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $KeyVaultSecret
                if ($CertAPI) {
                    $ThumbAPI = $CertAPI.Thumbprint  
                    $KeyVaultId="https://$KeyVaultName.vault.azure.net/secrets/$KeyVaultSecret"
                    "KeyVaultId = $KeyVaultId"
                    if ($ThumbAPI -ne $ThumbLets) { 
                        $UploadCert = $true
                    } 
                }
                else {
                    $UploadCert = $true
                }  
                if ($UploadCert) { 
                    $null = Import-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $KeyVaultSecret -FilePath $pfxPath -Password $securePassword
                } 
            } 

        }
        "AGW" {
            "AGW : Upload Certificate to keyvault ..."
            if ($KeyVault -ne "") {
                try {
                    $null = Import-AzKeyVaultCertificate -VaultName $KeyVault -Name $CertificateName -FilePath $pfxPath -Password $securePassword
                } 
                catch {
                    Write-Error "Error on uploading Certificate to $KeyVault !"
                    $ErrorJob++
                }
            } 
            $appGateway = Get-AzApplicationGateway -ResourceGroupName $ResourceGroupName -Name $Resources
            # Load cert
            "AGW : Adding SSL/TLS Certificate .."
            $curCert = Get-AzApplicationGatewaySslCertificate -ApplicationGateway $appGateway | Where-Object { $_.Name -eq $DomainName } | Select-Object -First 1

            if ($curCert) {
                $appGateway = Remove-AzApplicationGatewaySslCertificate -ApplicationGateway $appGateway -Name $DomainName
            }
            $appGateway = Add-AzApplicationGatewaySslCertificate -ApplicationGateway $appGateway -Name $DomainName -CertificateFile $pfxPath -Password $securePassword

            $cert = Get-AzApplicationGatewaySslCertificate -ApplicationGateway $appGateway -Name $DomainName
            $fpHttpsPort = (Get-AzApplicationGatewayFrontendPort -ApplicationGateway $appGateway | Where-Object { $_.Port -eq "443" })
            $fipconfig = (Get-AzApplicationGatewayFrontendIPConfig -ApplicationGateway $appGateway | Where-Object { $_.PublicIPAddress -NE $null })

            "AGW : Updating HTTPS Listener..."
            $null = Set-AzApplicationGatewayHttpListener -ApplicationGateway $appGateway -Name $EndPoint_Listener -Protocol Https -SslCertificate $cert -Hostname $DomainName -FrontendIPConfiguration $fipconfig -FrontendPort $fpHttpsPort

            "AGW : Saving changes..."
            # Commit the changes to Azure
            try {
                $null = Set-AzApplicationGateway -ApplicationGateway $appGateway
            } 
            catch {
                Write-Error "Error on updating ApplicationGateway !"
                $ErrorJob++
            }
        }
        {($_ -eq "VM") -or ($_ -eq "VMSS")}  {
            "VM : download update_cert.sh script ..."
            $null = Set-AzContext -Subscription "$VaultSubscription"
            $UpdateCertScriptB64 = Get-AzKeyVaultSecret -VaultName $VaultName -Name $UpdateCertSecret -AsPlainText
            $UpdateCertScript = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($UpdateCertScriptB64))
            $UpdateCertPath = Join-Path $pwd $UpdateCertName
            $UpdateCertScript | Set-Content -Path $UpdateCertPath

            $ResourceCtx = Set-AzContext -SubscriptionName "$SubscriptionName"

            $kvCreation = $false
            if ($KeyVault -ne "") {
                $KeyVaultObj = Get-AzKeyVault -VaultName $KeyVault -ResourceGroupName $ResourceGroupName
                if (!$KeyVaultObj) {
                    $kvCreation = $true
                }
            } 
            else {
                $kvCreation = $true
                $NameSuffix =  -join (([int][char]'a'..[int][char]'z') | Get-Random -Count 3 | % { [char] $_ })

                $KeyVault = $VaultName + $NameSuffix
                "  KeyVault = $KeyVault"
            } 
            if ($kvCreation) { 
                "  Keyvault Creation ..."
                $rg = Get-AzResourceGroup -Name $ResourceGroupName
                $KeyVaultObj = New-AzKeyVault -VaultName $KeyVault -ResourceGroupName $ResourceGroupName -Location $rg.location

                "  Set policy to keyvault ..."
                Set-AzKeyVaultAccessPolicy -VaultName $KeyVault -ResourceGroupName $ResourceGroupName -ObjectId $AutomationId -PermissionsToKeys get,list,delete,create,import,update -PermissionsToSecrets get,list,set,delete -PermissionsToCertificates get,list,delete,create,import,update
                Set-AzKeyVaultAccessPolicy -VaultName $KeyVault -ResourceGroupName $ResourceGroupName -EnabledForDeployment -EnabledForTemplateDeployment

                # Update des Tags
                $null = Set-AzContext -Subscription "$VaultSubscription"
                $ii=1
                $kv2=""
                $KeyvaultAll.Split("|") | ForEach {
                    if ( $ii -eq $ipos + 1 ) {
                        $kv2 = $kv2 + $KeyVault
                    }
                    else {
                        $kv2 = $kv2 + "$_"
                    }
                    if ( $ii -lt $KeyvaultAll.Split("|").Count ) {
                        $kv2 = $kv2 + "|"
                    }
                    $ii++
                }
                $KeyvaultAll=$kv2

                if( $CertTags['keyvault'] ) {
                    $CertTags['keyvault']=$CertTags['keyvault'] + "|$KeyVault"
                }
                else {
                    $CertTags['keyvault'] = $KeyVault
                } 
                $DNSSubscriptionName    = $CertTags['dns_subscription']
                $DNSResourceGroup       = $CertTags['dns_resource_group']
                $DNSzone                = $CertTags['dns_zone']
                $Tags = @{"dns_subscription"="$DNSSubscriptionName";"dns_resource_group"="$DNSResourceGroup";"dns_zone"="$DNSzone";"subscription"="$SubscriptionNameAll";"resource_group"="$ResourceGroupAll";"resource_type"="$ResourceTypeAll";"resources"="$ResourcesAll";"endpoint_listener"="$EndPoint_ListenerAll";"keyvault"="$KeyvaultAll"}
                $null = Update-AzKeyVaultCertificate -VaultName $VaultName -Name $CertificateName -Tag $Tags

                $ResourceCtx = Set-AzContext -SubscriptionName "$SubscriptionName"
            }
            $UploadCert = $false
            $CertVM = Get-AzKeyVaultCertificate -VaultName $KeyVault -Name $CertificateName
            if ($CertVM) {
                $ThumbVM = $CertVM.Thumbprint  
                if ($ThumbVM -ne $ThumbLets) { 
                    $UploadCert = $true
                } 
            }
            else {
                $UploadCert = $true
            }  
            if ($UploadCert) { 
                "  Import certificate  into keyvault ..."
                $null = Import-AzKeyVaultCertificate -VaultName $KeyVault -Name $CertificateName -FilePath $pfxPath -Password $securePassword
            } 

            $KeyVaultId = $KeyVaultObj.ResourceId
            $KeyVaultSecret = Get-AzKeyVaultSecret -VaultName $KeyVault -Name $CertificateName
            $CertUrl = $KeyVaultSecret.Id
            $ResourceCtx = Set-AzContext -SubscriptionName "$SubscriptionName"


            if ($ResourceType -eq "VMSS") { 
                "VMSS : Upload Cert in /var/lib/waagent"
                $Resources.Split(",") | ForEach {
                    $CurVMssName = $_
                    "  Add Secret to VMSS $CurVMssName ..."
                    " Get-AzVmss -ResourceGroupName $ResourceGroupName -VMScaleSetName $CurVMssName "
                    # Get current VMSS
                    $VMss = Get-AzVmss -ResourceGroupName $ResourceGroupName -VMScaleSetName $CurVMssName
                    if ($VMss) { 
                        #  $CertConfig = New-AzVmssVaultCertificateConfig -CertificateUrl $CertUrl -CertificateStore "Certificates"
                        $CertConfig = New-AzVmssVaultCertificateConfig -CertificateUrl $CertUrl
                        if ($VMss.VirtualMachineProfile.OsProfile.Secrets) { 
                            # Ref : https://docs.microsoft.com/fr-fr/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-faq#how-do-i-add-a-new-vault-certificate-to-a-new-certificate-object
                            # Add the new cert to the correct Secrets group.
                            $VMss.VirtualMachineProfile.OsProfile.Secrets[0].VaultCertificates.RemoveAt(0)
                            $VMss.VirtualMachineProfile.OsProfile.Secrets[0].VaultCertificates.Add($CertConfig)
                        }
                        else {  
                            Add-AzVmssSecret -VirtualMachineScaleSet $VMss -SourceVaultId $KeyVaultId -VaultCertificate $CertConfig
                        } 

                        try {
                            # Update VMSS with the changes.
                            Update-AzVmss -ResourceGroupName $ResourceGroupName -Name $CurVMssName -VirtualMachineScaleSet $VMss
                        }
                        catch {
                            Write-Error "Error on update VMss !"
                            $ErrorJob++
                        }  

                        $VMssInstances = Get-AzVmssVM -ResourceGroupName $ResourceGroupName -VMScaleSetName $CurVMssName -InstanceView

                        Foreach ($scaleSetInstance in $VMssInstances) {
                            $VMDeallocated = $false
                            $VMDetail = Get-AzVmssVM -ResourceGroupName $ResourceGroupName -VMScaleSetName $CurVMssName -InstanceView -InstanceId $scaleSetInstance.InstanceId
                            foreach ($VMStatus in $VMDetail.Statuses) { 
                                $VMStatusDetail = $VMStatus.DisplayStatus
                            } 
                            if ( $VMStatusDetail -eq "VM deallocated" ) { 
                                $VMDeallocated = $true
                                "  Starting of Instance $scaleSetInstance.InstanceId of VMSS $CurVMssName ..."
                                Start-AzVmss -ResourceGroupName $ResourceGroupName -VMScaleSetName $CurVMssName -InstanceId $scaleSetInstance.InstanceId
                            }
                            try {
                                Update-AzVmssInstance -ResourceGroupName $ResourceGroupName -VMScaleSetName $CurVMssName -InstanceId $scaleSetInstance.InstanceId
                                "  Run update_cert.sh script on Instance $scaleSetInstance.InstanceId of VMSS $CurVMssName ..."
                                Invoke-AzVmssVMRunCommand -ResourceGroupName $ResourceGroupName -VMScaleSetName $CurVMssName -InstanceId $scaleSetInstance.InstanceId -CommandId 'RunShellScript' -ScriptPath "$UpdateCertPath" -Parameter @{"arg1" = "$DomainName"; "arg2" = "$ThumbLets"}
                            }
                            catch {
                                Write-Error "Error on execute command on Instance of VMss !"
                                $ErrorJob++
                            } 

                            if ( $VMDeallocated ) { 
                                "  Stopping of Instance $scaleSetInstance.InstanceId of VMSS $CurVMssName  ..."
                                Stop-AzVmss -ResourceGroupName $ResourceGroupName -VMScaleSetName $CurVMssName -InstanceId $scaleSetInstance.InstanceId -Force
                            }

                        }
                    } 
                }
            }
            else {
                "VM : Upload Cert in /var/lib/waagent"

                $Resources.Split(",") | ForEach {
                    $CurVMName = $_
                    $VMDeallocated = $false
                    $VMDetail = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $CurVMName -Status
                    foreach ($VMStatus in $VMDetail.Statuses) { 
                        $VMStatusDetail = $VMStatus.DisplayStatus
                    }
                    if ( $VMStatusDetail -eq "VM deallocated" ) { 
                        $VMDeallocated = $true
                        "  Starting of VM $CurVMName ..."
                        Start-AzVM -ResourceGroupName $ResourceGroupName -Name $CurVMName
                    } 
                    $VM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $CurVMName
                    "  Add Secret to VM $CurVMName ..."
                    $VM = Add-AzVMSecret -VM $VM -SourceVaultId $KeyVaultId -CertificateUrl $CertUrl
                    Update-AzVM -ResourceGroupName $ResourceGroupName -VM $VM
                    "  Run update_cert.sh script ..."
                    try {
                        Invoke-AzVMRunCommand -VM $VM -CommandId 'RunShellScript'  -ScriptPath "$UpdateCertPath" -Parameter @{"arg1" = "$DomainName"; "arg2" = "$ThumbLets"}
                    }
                    catch {
                        Write-Error "Error on execute command on VM !"
                        $ErrorJob++
                    }  
                    "  Remove secret from VM ..."
                    $VM = Remove-AzVMSecret -VM $VM -SourceVaultId $KeyVaultId
                    try {
                        Update-AzVM -ResourceGroupName $ResourceGroupName -VM $VM
                    }
                    catch {
                        Write-Error "Error on update VM !"
                        $ErrorJob++
                    }
                    if ( $VMDeallocated ) { 
                        "  Stopping of VM $CurVMName ..."
                        Stop-AzVM -ResourceGroupName $ResourceGroupName -Name $CurVMName -Force
                    } 
                }
            }   
        }
    }
}

Remove-Item $pfxPath

if ( $ErrorJob -gt 0 ) {
    Write-Error "There are some Errors ! " -ErrorAction Stop
} 
