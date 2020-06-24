function New-Node {
  Param(
    [int32]
    $Index,
    [Microsoft.Azure.Commands.Network.Models.PSNetworkSecurityGroup]
    $NetworkSecurityGroup,
    [Microsoft.Azure.Commands.Network.Models.PSSubnet]
    $Subnet,
    [System.Management.Automation.PSCredential]
    $Credential,
    [string]
    $Username,
    [string]
    $VmSize
  )
  # Create a public IP address and specify a DNS name
  $PublicIpAddress = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $Location -Name "public-ip-$Index" -AllocationMethod Static -IdleTimeoutInMinutes 4

  # Create a virtual network card and associate with public IP address and NSG
  $NetworkInterface = New-AzNetworkInterface -Name "network-interface-$Index" -ResourceGroupName $ResourceGroupName -Location $Location -SubnetId $Subnet.Id -PublicIpAddressId $PublicIpAddress.Id -NetworkSecurityGroupId $NetworkSecurityGroup.Id

  $VmName = "node-$Index"
  # Create a virtual machine configuration
  $VmConfig = New-AzVMConfig -VMName $VmName -VMSize $VmSize |
  Set-AzVMOperatingSystem -Linux -ComputerName $VmName -Credential $Credential -DisablePasswordAuthentication |
  Set-AzVMSourceImage -PublisherName Canonical -Offer UbuntuServer -Skus 18.04-LTS -Version latest |
  Add-AzVMNetworkInterface -Id $NetworkInterface.Id

  # Configure SSH Keys
  $sshPublicKey = Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub"
  Add-AzVMSshPublicKey -VM $VmConfig -KeyData $sshPublicKey -Path "/home/$Username/.ssh/authorized_keys"

  # Create a virtual machine
  New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VmConfig
}

function Config-WorkerNode {
  Param(
    [int32]
    $Index,
    [string]
    $ResourceGroupName,
    [string]
    $Username,
    [string]
    $NodeContent
  )
  $NodeIp = (Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName).IpAddress[$Index]
  ssh -o "StrictHostKeyChecking no" $Username@$NodeIp $NodeContent
}

function Config-MasterNode {
  Param(
    [string]
    $ResourceGroupName,
    [string]
    $Username
  )
  $MasterIp = (Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName).IpAddress[0]
  $MasterContent = ((Get-Content -raw -Path ./kubernetes-master-node.sh) -replace 'x.x.x.x',$MasterIp) -replace "`r`n","`n"
  Write-Host $MasterContent
  ssh -o "StrictHostKeyChecking no" $Username@$MasterIp $MasterContent
  scp ${Username}@${MasterIp}:/home/${Username}/.kube/config ./${MasterIp}.yaml
  (Get-Content ./${MasterIp}.yaml).replace('192.168.1.4', ${MasterIp}) | Set-Content ./${MasterIp}.yaml
}

function New-AzureKubernetes {
  Param(
    [int32]
    $NodeCount,
    [string]
    $Username,
    [string]
    $Location = "EastUs",
    [string]
    $VmSize = "Standard_D4s_v3"
  )
  $ResourceGroupName = "$Username-kubernetes"

  $RandomPassword = -join(((65..90)+(35..38)+(97..122) | ForEach-Object {[char]$_})+(0..9) | Get-Random -Count 12)
  $SecuredPassword = ConvertTo-SecureString $RandomPassword -AsPlainText -Force
  $Credential = New-Object System.Management.Automation.PSCredential($Username, $SecuredPassword)

  New-AzResourceGroup -Name $ResourceGroupName -Location $Location

  # Create a subnet configuration
  $SubnetConfig = New-AzVirtualNetworkSubnetConfig -Name Subnet -AddressPrefix 192.168.1.0/24

  # Create a virtual network
  $VirtualNetwork = New-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Location $Location `
    -Name vNET -AddressPrefix 192.168.0.0/16 -Subnet $SubnetConfig

  # Create an inbound network security group rule for port SSH
  $NetworkSecurityRuleSSH = New-AzNetworkSecurityRuleConfig -Name NetworkSecurityGroupRuleSSH  -Protocol Tcp `
    -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * `
    -DestinationPortRange 22 -Access Allow

  # Create an inbound network security group rule for Kubectl
  $NetworkSecurityRuleK8s = New-AzNetworkSecurityRuleConfig -Name NetworkSecurityGroupRuleK8s  -Protocol Tcp `
    -Direction Inbound -Priority 1001 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * `
    -DestinationPortRange 6443 -Access Allow

  # Create a network security group
  $NetworkSecurityGroup = New-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Location $Location -Name NetworkSecurityGroup -SecurityRules $NetworkSecurityRuleSSH,$NetworkSecurityRuleK8s

  for ($Index = 0; $Index -lt $NodeCount; $Index++) {
    New-Node -Index $Index -Nsg $NetworkSecurityGroup -Subnet $VirtualNetwork.Subnets[0] -Credential $Credential -Username $Username -VmSize $VmSize
  }

  Config-MasterNode -ResourceGroupName $ResourceGroupName -Username $Username

  $NodeContent = (Get-Content -raw -Path ./kubernetes-worker-node.sh) -replace "`r`n","`n"
  for ($Index = 1; $Index -lt $NodeCount; $Index++) {
    Config-WorkerNode -Index $Index -ResourceGroupName $ResourceGroupName -Username $Username -NodeContent $NodeContent
  }
}
