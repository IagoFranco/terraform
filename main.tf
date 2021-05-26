terraform {
    required_version = ">= 0.14.9"
    
    required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }
}

provider "azurerm" {
    skip_provider_registration = true
  features {}
}

resource "azurerm_resource_group" "rgterraformasd02" {
  name     = "rgterraformasd02"
  location = "eastus2"
  tags = {
    "Environment" = "Trabalho Terraform"
  }
}

resource "azurerm_virtual_network" "vnterraformasd02" {
  name                = "vnterraformasd02"
  location            = azurerm_resource_group.rgterraformasd02.location
  resource_group_name = azurerm_resource_group.rgterraformasd02.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "snterraformasd02" {
  name = "snterraformasd02"
  resource_group_name = azurerm_resource_group.rgterraformasd02.name
  virtual_network_name = azurerm_virtual_network.vnterraformasd02.name
  address_prefixes = ["10.0.2.0/24"]

  depends_on = [azurerm_resource_group.rgterraformasd02, azurerm_virtual_network.vnterraformasd02]
}

resource "azurerm_public_ip" "pipgterraformasd02" {
  allocation_method = "Static"
  location = azurerm_resource_group.rgterraformasd02.location
  name = "pipgterraformasd02"
  resource_group_name = azurerm_resource_group.rgterraformasd02.name

  depends_on = [azurerm_resource_group.rgterraformasd02]
}

resource "azurerm_network_security_group" "nsgterraformasd02" {
  location = azurerm_resource_group.rgterraformasd02.location
  name = "nsgterraformasd02"
  resource_group_name = azurerm_resource_group.rgterraformasd02.name

  security_rule {
    name = "SSH"
    access = "Allow"
    direction = "Inbound"
    priority = 1002
    protocol = "Tcp"
    destination_port_range = "22"
    source_port_range = "*"
    source_address_prefix = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name = "mysql"
    access = "Allow"
    direction = "Inbound"
    priority = 1001
    protocol = "Tcp"
    destination_port_range = "3306"
    source_port_range = "*"
    source_address_prefix = "*"
    destination_address_prefix = "*"
  }

  depends_on = [azurerm_resource_group.rgterraformasd02]
}

resource "azurerm_network_interface" "nicterraformasd02" {
  name = "nicterraformasd02"
  location = azurerm_resource_group.rgterraformasd02.location
  resource_group_name = azurerm_resource_group.rgterraformasd02.name

  ip_configuration {
    name = "myNicConfiguration"
    private_ip_address_allocation = "Dynamic"
    subnet_id = azurerm_subnet.snterraformasd02.id
    public_ip_address_id = azurerm_public_ip.pipgterraformasd02.id
  }

  depends_on = [azurerm_resource_group.rgterraformasd02, azurerm_public_ip.pipgterraformasd02, azurerm_subnet.snterraformasd02]
}

resource "azurerm_network_interface_security_group_association" "sgaterraformasd02" {
  network_interface_id = azurerm_network_interface.nicterraformasd02.id
  network_security_group_id = azurerm_network_security_group.nsgterraformasd02.id

  depends_on = [azurerm_network_interface.nicterraformasd02, azurerm_network_security_group.nsgterraformasd02]
}

resource "azurerm_storage_account" "saterraformasd02" {
  name = "saterraformasd02"
  account_replication_type = "LRS"
  account_tier = "Standard"
  location = azurerm_resource_group.rgterraformasd02.location
  resource_group_name = azurerm_resource_group.rgterraformasd02.name
}

resource "azurerm_linux_virtual_machine" "vmterraformasd02" {
  name = "vmterraformasd02"
  computer_name = "myVm"
  admin_username = var.user
  admin_password = var.password
  disable_password_authentication = false
  location = azurerm_resource_group.rgterraformasd02.location
  resource_group_name = azurerm_resource_group.rgterraformasd02.name
  size = "Standard_DS1_v2"
  network_interface_ids = [
    azurerm_network_interface.nicterraformasd02.id
  ]

  os_disk {
    name = "mysqlDisk"
    caching = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.saterraformasd02.primary_blob_endpoint
  }

  source_image_reference {
    publisher = "Canonical"
    offer = "UbuntuServer"
    sku = "18.04-LTS"
    version = "latest"
  }

  depends_on = [azurerm_resource_group.rgterraformasd02, azurerm_network_interface.nicterraformasd02, azurerm_storage_account.saterraformasd02]
}

output "public_ip_address_mysql" {
  value = azurerm_public_ip.pipgterraformasd02.ip_address
}

resource "time_sleep" "wait_30_seconds_db" {
  create_duration = "30s"
  depends_on = [azurerm_linux_virtual_machine.vmterraformasd02]
}

resource "null_resource" "upload_sql" {
  provisioner "file" {
    connection {
      type = "ssh"
      host = azurerm_public_ip.pipgterraformasd02.ip_address
      user = var.user
      password = var.password
    }

    source = "config"
    destination = "/home/azureuser"
  }

  depends_on = [time_sleep.wait_30_seconds_db]
}

resource "null_resource" "deploy_db" {
  triggers = {
    order = null_resource.upload_sql.id
  }

  provisioner "remote-exec" {
    connection {
      type = "ssh"
      host = azurerm_public_ip.pipgterraformasd02.ip_address
      user = var.user
      password = var.password
    }

    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y mysql-server-5.7",
      "sudo mysql < /home/azureuser/config/user.sql",
      "sudo cp -f /home/azureuser/config/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf",
      "sudo service mysql restart",
      "sleep 30",
    ]
  }
}