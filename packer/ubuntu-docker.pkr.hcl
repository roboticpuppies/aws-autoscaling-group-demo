packer {
  required_plugins {
    amazon = {
      version = ">= 1.4.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "ap-southeast-3"
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "ami_name_prefix" {
  type    = string
  default = "ubuntu-docker"
}

source "amazon-ebs" "ubuntu" {
  region        = var.aws_region
  instance_type = var.instance_type
  ami_name      = "${var.ami_name_prefix}-{{timestamp}}"

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["099720109477"] # Canonical
    most_recent = true
  }

  ssh_username = "ubuntu"

  tags = {
    Name      = "${var.ami_name_prefix}-{{timestamp}}"
    OS        = "Ubuntu 24.04 LTS"
    Builder   = "packer"
    BuildDate = "{{timestamp}}"
  }
}

build {
  sources = ["source.amazon-ebs.ubuntu"]

  provisioner "shell" {
    script          = "scripts/install-docker.sh"
    execute_command = "sudo -S bash '{{.Path}}'"
  }

  provisioner "shell" {
    script          = "scripts/install-awscli.sh"
    execute_command = "sudo -S bash '{{.Path}}'"
  }

  provisioner "shell" {
    script          = "scripts/install-node-exporter.sh"
    execute_command = "sudo -S bash '{{.Path}}'"
  }

  provisioner "shell" {
    script          = "scripts/setup-zsh.sh"
    execute_command = "sudo -S bash '{{.Path}}'"
  }

  provisioner "shell" {
    script          = "scripts/setup-auto-update.sh"
    execute_command = "sudo -S bash '{{.Path}}'"
  }
}
