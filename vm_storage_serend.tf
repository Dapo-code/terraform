# This file creates a vm a storage account and a service endpoint in a subnet to connect the vm to a storage account
#____________________________________________________________________________________________________________________
# Local.tf: This files setsup the local variables
locals {
  resource_group_name = "app-grp"
  location = "Central India"
  virtual_network = {
    name = "app-network"
    address_space = "10.0.0.0/16"
  }
  virtual_machine_name = "app-vm"
  storage_account_name = "vmstore890321"
}
#_____________________________________________________________________________________________________________________
# Variable.tf: this file sets up numbers of certain resourecs to be created
variable "number_of_subnets" {
    type = number
    description = "This defines the number os subnets in a network"
    default = 2 
    validation {
      condition = var.number_of_subnets < 5
      error_message = "The number of subnets must be less than 5."
    }
}

variable "number_of_machines" {
    type = number
    description = "this defines the number of Virtual machines"
    default = 2
    validation {
      condition = var.number_of_machines < 5
      error_message = "The number of machines must be less than 5"
    }

  
}
#___________________________________________________________________________________________________________________________
# RG.tf: creates respource group
resource "azurerm_resource_group" "appgrp" {
  name     = local.resource_group_name
  location = local.location
}

#___________________________________________________________________________________________________________________________
# Network.tf: this creates the network, subnets with service endpoint and NSG
resource "azurerm_virtual_network" "appnetwork" {
  name                = local.virtual_network.name
  location            = azurerm_resource_group.appgrp.location
  resource_group_name = azurerm_resource_group.appgrp.name
  address_space       = [local.virtual_network.address_space]
 
  depends_on = [ azurerm_resource_group.appgrp ]
  }

resource "azurerm_subnet" "subnets" {
  count = var.number_of_subnets
  name                 = "subnets${count.index}"
  resource_group_name  = local.resource_group_name
  virtual_network_name = local.virtual_network.name
  address_prefixes     = ["10.0.${count.index}.0/24"]
  service_endpoints = [ "Microsoft.Storage" ]

  depends_on = [ azurerm_virtual_network.appnetwork ]
}

resource "azurerm_network_security_group" "appnsg" {
  name                = "app-nsg"
  location            = local.location
  resource_group_name = local.resource_group_name

  security_rule {
    name                       = "allowRDP"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  depends_on = [ azurerm_resource_group.appgrp ]

}

resource "azurerm_subnet_network_security_group_association" "appnsglink" {
  count = var.number_of_subnets
  subnet_id = azurerm_subnet.subnets[count.index].id
  network_security_group_id = azurerm_network_security_group.appnsg.id

  depends_on = [ azurerm_network_security_group.appnsg ]
}
#___________________________________________________________________________________________________________________________
# vm.tf: This file creates vms with ni and associate the vms with key vault for password

resource "azurerm_network_interface" "appinterface" {
  count = var.number_of_machines
  name                = "app-interface${count.index}"
  location            = local.location
  resource_group_name = local.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnets[count.index].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.appip[count.index].id
  }

  depends_on = [ azurerm_subnet.subnets, azurerm_public_ip.appip ]
}


resource "azurerm_public_ip" "appip" {
  count = var.number_of_machines
  name                = "app-ip${count.index}"
  resource_group_name = local.resource_group_name
  location            = local.location
  allocation_method   = "Static"

  depends_on = [ azurerm_resource_group.appgrp ]

}

/*  data blocks are used to define resources that exists outside of the terraform configuration like a keyvault
*/
data "azurerm_key_vault" "keyvault67854" {
  name                = "keyvault67854"
  resource_group_name = "keyvault-grp"
}

data "azurerm_key_vault_secret" "vmpasswd" {
  name         = "vmpasswd"
  key_vault_id = data.azurerm_key_vault.keyvault67854.id
}

resource "azurerm_windows_virtual_machine" "appvm" {
  count = var.number_of_machines
  name                = "${local.virtual_machine_name}${count.index}"
  resource_group_name = local.resource_group_name
  location            = local.location
  size                = "Standard_D2s_v3"
  admin_username      = "dapo"
  admin_password      = data.azurerm_key_vault_secret.vmpasswd.value
  network_interface_ids = [
    azurerm_network_interface.appinterface[count.index].id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  depends_on = [ azurerm_network_interface.appinterface, azurerm_resource_group.appgrp ]
}
#___________________________________________________________________________________________________________________________
# storage.tf: This file creates a storage account with networking rules
resource "azurerm_storage_account" "vmstore" {
  count = var.number_of_subnets
  name                     = local.storage_account_name
  resource_group_name      = local.resource_group_name
  location                 = local.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind = "StorageV2"  

  network_rules {
    default_action             = "Deny"
    ip_rules                   = ["90.212.4.62"]
    virtual_network_subnet_ids = [azurerm_subnet.subnets[0].id]
  }

  depends_on = [
    azurerm_resource_group.appgrp,
    azurerm_subnet.subnets
   ]
}

resource "azurerm_storage_container" "data" {
  name                  = "data"
  storage_account_name  = local.storage_account_name
  container_access_type = "blob"
  depends_on=[
    azurerm_storage_account.vmstore
    ]
}

resource "azurerm_storage_blob" "IISConfig" {
  name                   = "IIS_Config.ps1"
  storage_account_name   = local.storage_account_name
  storage_container_name = "data"
  type                   = "Block"
  source                 = "IIS_Config.ps1"
   depends_on=[azurerm_storage_container.data]
}

