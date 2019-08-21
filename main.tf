data "openstack_networking_network_v2" "network" {
    name                = "${var.network_name}"
}

data "openstack_networking_subnet_v2" "subnet" {
    name                = "${var.subnet_name}"
}

resource "openstack_compute_keypair_v2" "terraform_key" {
    name                = "terraform-key"
    public_key          = "${file(var.ssh_key_public)}"
}

resource "openstack_compute_secgroup_v2" "thor_master" {
  name                  = "thor-master"
  description           = "Allows communication with thor master"

  rule {
    from_port           = 8000
    to_port             = 9000
    ip_protocol         = "tcp"
    cidr                = "0.0.0.0/0"
  }
}

resource "openstack_networking_port_v2" "thor_master_port" {
    name                = "thor-master-port"
    network_id          = "${data.openstack_networking_network_v2.network.id}"

    fixed_ip {
        subnet_id       = "${data.openstack_networking_subnet_v2.subnet.id}"
        ip_address      = "${cidrhost(data.openstack_networking_subnet_v2.subnet.cidr, 5)}"
    }
}

resource "openstack_networking_port_v2" "thor_slave_port" {
    count               = "${var.thor_slave_count}"

    name                = "${format("thor-slave-port-%03d", count.index + 1)}"
    network_id          = "${data.openstack_networking_network_v2.network.id}"

    fixed_ip {
        subnet_id       = "${data.openstack_networking_subnet_v2.subnet.id}"
        ip_address      = "${cidrhost(data.openstack_networking_subnet_v2.subnet.cidr, 5 + count.index + 1)}"
    }
}

resource "openstack_blockstorage_volume_v2" "thor_master_volume" {
    name                = "thor-master-volume"
    size                = "${var.thor_master_disk}"
}

resource "openstack_blockstorage_volume_v2" "thor_slave_volume" {
    count               = "${var.thor_slave_count}"

    name                = "${format("thor-slave-volume-%03d", count.index + 1)}"
    size                = "${floor((var.total_disk - var.thor_master_disk) / var.thor_slave_count)}"
}

resource "openstack_compute_instance_v2" "thor_master" {
    name                = "thor-master"
    image_name          = "${var.image_name}"
    flavor_name         = "${var.thor_master_flavor_name}"
    key_pair            = "${openstack_compute_keypair_v2.terraform_key.name}"
    security_groups     = ["${openstack_compute_secgroup_v2.thor_master.name}","default"]
    availability_zone   = "${openstack_blockstorage_volume_v2.thor_master_volume.availability_zone}"
    user_data           = "${data.template_file.thor_master_user_data.rendered}"
    
    network {
        port            = "${openstack_networking_port_v2.thor_master_port.id}"
    }
}

resource "openstack_compute_instance_v2" "thor_slave" {
    count               = "${var.thor_slave_count}"

    name                = "${format("thor-slave-%03d", count.index + 1)}"
    image_name          = "${var.image_name}"
    flavor_name         = "${var.thor_slave_flavor_name}"
    key_pair            = "${openstack_compute_keypair_v2.terraform_key.name}"
    security_groups     = ["default"]
    availability_zone   = "${element(openstack_blockstorage_volume_v2.thor_slave_volume.*.availability_zone, count.index)}"
    user_data           = "${element(data.template_file.thor_slave_user_data.*.rendered, count.index)}"
    
    network {
        port            = "${element(openstack_networking_port_v2.thor_slave_port.*.id, count.index)}"
    }
}

resource "openstack_compute_volume_attach_v2" "thor_master_attach" {
    instance_id         = "${openstack_compute_instance_v2.thor_master.id}"
    volume_id           = "${openstack_blockstorage_volume_v2.thor_master_volume.id}"
    device              = "${var.device}"
}

resource "openstack_compute_volume_attach_v2" "thor_slave_attach" {
    count               = "${var.thor_slave_count}"

    instance_id         = "${element(openstack_compute_instance_v2.thor_slave.*.id, count.index)}"
    volume_id           = "${element(openstack_blockstorage_volume_v2.thor_slave_volume.*.id, count.index)}"
    device              = "${var.device}"
}