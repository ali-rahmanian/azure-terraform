terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "mtc-rg" {
  name     = "mtc-rg"
  location = var.location
  tags = {
    environment = var.envinronment
  }
}

resource "azurerm_virtual_network" "mtc_vn" {
  name                = "${var.prefix}-network"
  resource_group_name = azurerm_resource_group.mtc-rg.name
  location            = azurerm_resource_group.mtc-rg.location
  address_space       = ["10.123.0.0/16"] #known as cird block
  tags = {
    environment = "dev"
  }
}

resource "azurerm_subnet" "mtc-subnet" {
  name                 = "${var.prefix}-subnet"
  resource_group_name  = azurerm_resource_group.mtc-rg.name
  virtual_network_name = azurerm_virtual_network.mtc_vn.name
  address_prefixes     = ["10.123.1.0/24"]
}


resource "azurerm_network_security_group" "mtc-sg" {
  name                = "${var.prefix}-sg"
  location            = azurerm_resource_group.mtc-rg.location
  resource_group_name = azurerm_resource_group.mtc-rg.name

  tags = {
    environment = var.envinronment
  }
}

resource "azurerm_network_security_rule" "mtc-dev-rule" {
  name                        = "${var.prefix}-dev-rule"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.mtc-rg.name
  network_security_group_name = azurerm_network_security_group.mtc-sg.name
}


resource "azurerm_subnet_network_security_group_association" "mtc-sga" {
  subnet_id                 = azurerm_subnet.mtc-subnet.id
  network_security_group_id = azurerm_network_security_group.mtc-sg.id
}


resource "azurerm_public_ip" "mtc-ip" {
  name                = "${var.prefix}-ip"
  resource_group_name = azurerm_resource_group.mtc-rg.name
  location            = azurerm_resource_group.mtc-rg.location
  allocation_method   = "Dynamic"

  tags = {
    environment = var.envinronment
  }
}

resource "azurerm_network_interface" "mtc-nic" {
  name                = "${var.prefix}-nic"
  resource_group_name = azurerm_resource_group.mtc-rg.name
  location            = azurerm_resource_group.mtc-rg.location
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.mtc-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.mtc-ip.id
  }

  tags = {
    environment = var.envinronment
  }
}


resource "azurerm_linux_virtual_machine" "mtc-vm" {
  name                = "${var.prefix}-vm"
  resource_group_name = azurerm_resource_group.mtc-rg.name
  location            = azurerm_resource_group.mtc-rg.location
  size                = "Standard_D2s_v3"
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  network_interface_ids = [
    azurerm_network_interface.mtc-nic.id,
  ]

  admin_ssh_key {
    username = "adminuser"

    public_key = file("~/.ssh/mtcazurekey.pub")
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntuserver"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS" #"Standard_D2s_v3"
    caching              = "ReadWrite"
  }

  tags = {
    environment = var.envinronment
  }

  provisioner "local-exec" {
    command = templatefile("linux-ssh-script.tpl", {
      hostname     = self.public_ip_address,
      user         = "adminuser",
      identityfile = "~/.ssh/mtcazurekey"
    })
    interpreter = ["bash", "-c"]
  }
}


data "azurerm_public_ip" "mtc_ip_date" {
  name                = azurerm_public_ip.mtc-ip.name
  resource_group_name = azurerm_resource_group.mtc-rg.name
}



