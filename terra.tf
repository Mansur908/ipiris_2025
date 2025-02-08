terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.84"
    }
  }
}

provider "yandex" {
  token     = var.yandex_api_token
  cloud_id  = var.yandex_cloud_id
  folder_id = var.yandex_folder_id
  zone      = "ru-central1-a"
}

resource "yandex_vpc_network" "custom_network" {
  name = "custom-network"
}

resource "yandex_vpc_subnet" "app_subnet" {
  name           = "app-subnet"
  network_id     = yandex_vpc_network.custom_network.id
  v4_cidr_blocks = ["10.0.0.0/24"]
  zone           = "ru-central1-a"
}

resource "tls_private_key" "vm_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "local_file" "ssh_private_key" {
  content  = tls_private_key.vm_ssh_key.private_key_pem
  filename = "./private_ssh_key.pem"
}

resource "null_resource" "set_key_permissions" {
  depends_on = [local_file.ssh_private_key]

  provisioner "local-exec" {
    command = "chmod 600 ./private_ssh_key.pem"
  }
}

resource "yandex_compute_instance" "web_server" {
  name        = "web-server"
  platform_id = "standard-v3"

  resources {
    cores         = 2
    memory        = 4
    core_fraction = 100
  }

  boot_disk {
    initialize_params {
      image_id = "fd8bpal18cm4kprpjc2m" # Ubuntu 24.04 LTS
      size     = 20
      type     = "network-ssd"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.app_subnet.id
    nat       = true
  }

  metadata = {
    user-data = <<-EOF
      #cloud-config
      ssh_pwauth: no
      users:
        - name: devops
          groups: sudo
          sudo: 'ALL=(ALL) NOPASSWD:ALL'
          shell: /bin/bash
          ssh_authorized_keys:
            - ${tls_private_key.vm_ssh_key.public_key_openssh}

      write_files:
      - path: /etc/motd
        content: "Welcome to your Yandex Cloud instance!"
        permissions: '0644'

      runcmd:
        - [ sudo, apt, update ]
        - [ sudo, apt, install, -y, docker.io ]
        - [ sudo, systemctl, enable, --now, docker ]
        - [ sleep, 15 ]
        - [ sudo, docker, run, -d, --restart=always, -p, "80:8080", jmix/jmix-bookstore ]
    EOF
  }
}

output "ssh_access" {
  value = "ssh -i ./private_ssh_key.pem devops@${yandex_compute_instance.web_server.network_interface.0.nat_ip_address}"
}

output "web_application_url" {
  value = "http://${yandex_compute_instance.web_server.network_interface.0.nat_ip_address}:80"
}

variable "yandex_api_token" {}
variable "yandex_cloud_id" {}
variable "yandex_folder_id" {}
