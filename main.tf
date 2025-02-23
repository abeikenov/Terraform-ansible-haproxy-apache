terraform {
  required_providers {
    openstack = {
      source = "terraform-provider-openstack/openstack"
    }
  }
}

provider "openstack" {
  auth_url    = ""
  user_name   = ""
  password    = ""
  tenant_name = ""
  region      = ""
}

resource "tls_private_key" "terraform_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content  = tls_private_key.terraform_key.private_key_pem
  filename = "${path.module}/terraform_key.pem"
}

resource "local_file" "public_key" {
  content  = tls_private_key.terraform_key.public_key_openssh
  filename = "${path.module}/terraform_key.pub"
}

resource "openstack_compute_keypair_v2" "terraform_keypair" {
  name       = "terraform_generated_key"
  public_key = tls_private_key.terraform_key.public_key_openssh
}

resource "openstack_networking_floatingip_v2" "haproxy_floating_ip" {
  pool = "FloatingIP Net"
}

data "openstack_networking_network_v2" "network" {
  name = "test_task_network"
}

resource "openstack_blockstorage_volume_v3" "haproxy_data" {
  name        = "haproxy_data"
  size        = 20
  volume_type = ""
  image_id    = ""
}

resource "openstack_compute_instance_v2" "haproxy" {
  name            = "haproxy"
  flavor_name     = ""
  key_pair        = openstack_compute_keypair_v2.terraform_keypair.name
  security_groups = [""]
  config_drive    = true

  block_device {
    uuid                  = openstack_blockstorage_volume_v3.haproxy_data.id
    source_type           = "volume"
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }

network {
    name        = ""
    fixed_ip_v4 = "192.168.0.104"
  }

user_data = <<-EOF
  #cloud-config
  runcmd:
    - sudo sed -i 's/^mirrorlist/#mirrorlist/' /etc/yum.repos.d/CentOS-Base.repo
    - sudo sed -i 's/^#baseurl/baseurl/' /etc/yum.repos.d/CentOS-Base.repo
    - sudo sed -i 's|http://mirror.centos.org/centos/\$releasever|https://vault.centos.org/7.9.2009|g' /etc/yum.repos.d/CentOS-Base.repo
EOF
}

resource "openstack_blockstorage_volume_v3" "ansible_data" {
  name        = "ansible_data"
  size        = 20
  volume_type = ""
  image_id    = ""
}

resource "openstack_compute_instance_v2" "ansible" {
  name            = "ansible"
  flavor_name     = ""
  key_pair        = openstack_compute_keypair_v2.terraform_keypair.name
  security_groups = [""]
  config_drive    = true

  block_device {
    uuid                  = openstack_blockstorage_volume_v3.ansible_data.id
    source_type           = "volume"
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }

network {
    name        = ""
    fixed_ip_v4 = "192.168.0.100"
  }
user_data = <<-EOF
  #cloud-config
  runcmd:
    - sudo sed -i 's/^mirrorlist/#mirrorlist/' /etc/yum.repos.d/CentOS-Base.repo
    - sudo sed -i 's/^#baseurl/baseurl/' /etc/yum.repos.d/CentOS-Base.repo
    - sudo sed -i 's|http://mirror.centos.org/centos/\$releasever|https://vault.centos.org/7.9.2009|g' /etc/yum.repos.d/CentOS-Base.repo
    - sudo yum install -y epel-release
    - sudo yum install -y git python3 python3-pip
    - sudo yum install -y ansible
    - mkdir /tmp/ansible
    - git clone https://github.com/abeikenov/ansible_roles.git /tmp/ansible
    - chown -R centos:centos /tmp/ansible
EOF
}

resource "openstack_blockstorage_volume_v3" "apache_data" {
  count       = 3
  name        = "apache_data_${count.index + 1}"
  size        = 20
  volume_type = ""
  image_id    = ""
}

resource "openstack_compute_instance_v2" "apache" {
  count          = 3
  name           = "apache-${count.index + 1}"
  flavor_name    = ""
  key_pair       = openstack_compute_keypair_v2.terraform_keypair.name
  security_groups = [""]
  config_drive   = true

  block_device {
    uuid                  = openstack_blockstorage_volume_v3.apache_data[count.index].id
    source_type           = "volume"
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }

network {
    name        = ""
    fixed_ip_v4 = "192.168.0.10${count.index + 1}"
  }

user_data = <<-EOF
  #cloud-config
  runcmd:
    - sudo sed -i 's/^mirrorlist/#mirrorlist/' /etc/yum.repos.d/CentOS-Base.repo
    - sudo sed -i 's/^#baseurl/baseurl/' /etc/yum.repos.d/CentOS-Base.repo
    - sudo sed -i 's|http://mirror.centos.org/centos/\$releasever|https://vault.centos.org/7.9.2009|g' /etc/yum.repos.d/CentOS-Base.repo
EOF
}

data "openstack_networking_port_v2" "haproxy_port" {
  network_id = data.openstack_networking_network_v2.network.id
  device_id  = openstack_compute_instance_v2.haproxy.id
}

resource "openstack_networking_floatingip_associate_v2" "haproxy_fip_association" {
  floating_ip = openstack_networking_floatingip_v2.haproxy_floating_ip.address
  port_id     = data.openstack_networking_port_v2.haproxy_port.id
}

resource "null_resource" "copy_ssh_key" {
  depends_on = [openstack_compute_instance_v2.ansible]

  provisioner "file" {
    source      = "${path.module}/terraform_key.pem"
    destination = "/home/centos/terraform_key.pem"

    connection {
      type        = "ssh"
      user        = "centos"
      private_key = tls_private_key.terraform_key.private_key_pem
      host        = openstack_compute_instance_v2.ansible.access_ip_v4
      agent       = false
    }
  }
}


resource "null_resource" "ansible_provisioner" {
  depends_on = [
    openstack_compute_instance_v2.ansible,
    openstack_compute_instance_v2.haproxy,
    openstack_compute_instance_v2.apache
  ]

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "centos"
      private_key = tls_private_key.terraform_key.private_key_pem
      host        = openstack_compute_instance_v2.ansible.access_ip_v4
	  agent       = false
    }

    inline = [
      "sleep 300",
      "chmod 600 /home/centos/terraform_key.pem",
      "mv /home/centos/terraform_key.pem /tmp/ansible/terraform_key.pem",
      "echo '[haproxy_servers]' > /tmp/ansible/hosts",
      "echo '192.168.0.104' >> /tmp/ansible/hosts",
      "echo '[apache_servers]' >> /tmp/ansible/hosts",
      "echo '192.168.0.101' >> /tmp/ansible/hosts",
      "echo '192.168.0.102' >> /tmp/ansible/hosts",
      "echo '192.168.0.103' >> /tmp/ansible/hosts",
      "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i /tmp/ansible/hosts /tmp/ansible/playbook.yml --private-key /tmp/ansible/terraform_key.pem"
    ]
  }
}
