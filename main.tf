data "openstack_networking_network_v2" "network" {
    name                = "${var.network_name}"
}

data "openstack_networking_subnet_v2" "subnet" {
    name                = "${var.subnet_name}"
}

data "openstack_networking_secgroup_v2" "default" {
    name                = "default"
}

resource "openstack_compute_keypair_v2" "terraform_key" {
    name                = "terraform-key"
    public_key          = "${file(var.ssh_key_public)}"
}

resource "openstack_networking_secgroup_v2" "thor_portal" {
    name                = "thor-portal"
    description         = "Allows communication from remote users"
}

resource "openstack_networking_secgroup_rule_v2" "thor_portal_rule_1" {
    direction           = "ingress"
    ethertype           = "IPv4"
    protocol            = "tcp"
    port_range_min      = 8000
    port_range_max      = 9000
    remote_ip_prefix    = "0.0.0.0/0"
    security_group_id   = "${openstack_networking_secgroup_v2.thor_portal.id}"
}

resource "openstack_networking_secgroup_rule_v2" "thor_portal_rule_2" {
    direction           = "ingress"
    ethertype           = "IPv4"
    protocol            = "tcp"
    port_range_min      = 7077
    port_range_max      = 7077
    remote_ip_prefix    = "0.0.0.0/0"
    security_group_id   = "${openstack_networking_secgroup_v2.thor_portal.id}"
}

resource "openstack_networking_port_v2" "thor_support_port" {
    count               = "${length(var.support_nodes)}"

    name                = "${format("thor-support-port-%02d", count.index + 1)}"
    network_id          = "${data.openstack_networking_network_v2.network.id}"

    security_group_ids  = ["${openstack_networking_secgroup_v2.thor_portal.id}","${data.openstack_networking_secgroup_v2.default.id}"]

    fixed_ip {
        subnet_id       = "${data.openstack_networking_subnet_v2.subnet.id}"
        ip_address      = "${cidrhost(data.openstack_networking_subnet_v2.subnet.cidr, 5 + count.index)}"
    }
}

resource "openstack_networking_port_v2" "thor_slave_port" {
    count               = "${var.thor_slave_count}"

    name                = "${format("thor-slave-port-%03d", count.index + 1)}"
    network_id          = "${data.openstack_networking_network_v2.network.id}"

    security_group_ids  = ["${data.openstack_networking_secgroup_v2.default.id}"]


    fixed_ip {
        subnet_id       = "${data.openstack_networking_subnet_v2.subnet.id}"
        ip_address      = "${cidrhost(data.openstack_networking_subnet_v2.subnet.cidr, 5 + length(var.support_nodes) + count.index)}"
    }
}

resource "openstack_blockstorage_volume_v2" "thor_support_volume" {
    count               = "${length(var.support_nodes)}"

    name                = "${format("thor-support-volume-%02d", count.index + 1)}"
    size                = "${var.support_nodes[count.index].disk}"
}

resource "openstack_blockstorage_volume_v2" "thor_slave_volume" {
    count               = "${var.thor_slave_count}"

    name                = "${format("thor-slave-volume-%03d", count.index + 1)}"
    size                = "${floor(var.thor_slave_total_disk / var.thor_slave_count)}"
}

resource "openstack_compute_instance_v2" "thor_support" {
    count               = "${length(var.support_nodes)}"

    name                = "${format("thor-support-%02d", count.index + 1)}"
    image_name          = "${var.image_name}"
    flavor_name         = "${var.support_nodes[count.index].flavor_name}"
    key_pair            = "${openstack_compute_keypair_v2.terraform_key.name}"
    availability_zone   = "${element(openstack_blockstorage_volume_v2.thor_support_volume.*.availability_zone, count.index)}"
    user_data           = "${element(data.template_file.thor_support_user_data.*.rendered, count.index)}"
    
    network {
        port            = "${element(openstack_networking_port_v2.thor_support_port.*.id, count.index)}"
    }

    provisioner "file" {
        content         = "${var.environment_filename == "" ? " " : file("${path.module}/files/${var.environment_filename}")}"
        destination     = "/tmp/environment.xml"
    
        connection {
            type        = "ssh"
            user        = "centos"
            host        = "${element(openstack_networking_port_v2.thor_support_port.*.all_fixed_ips.0, count.index)}"
            private_key = "${file(var.ssh_key_private)}"
            agent       = false
        }
    }
}

resource "openstack_compute_instance_v2" "thor_slave" {
    count               = "${var.thor_slave_count}"

    name                = "${format("thor-slave-%03d", count.index + 1)}"
    image_name          = "${var.image_name}"
    flavor_name         = "${var.thor_slave_flavor_name}"
    key_pair            = "${openstack_compute_keypair_v2.terraform_key.name}"
    availability_zone   = "${element(openstack_blockstorage_volume_v2.thor_slave_volume.*.availability_zone, count.index)}"
    user_data           = "${element(data.template_file.thor_slave_user_data.*.rendered, count.index)}"
    
    network {
        port            = "${element(openstack_networking_port_v2.thor_slave_port.*.id, count.index)}"
    }

    provisioner "file" {
        content         = "${var.environment_filename == "" ? " " : file("${path.module}/files/${var.environment_filename}")}"
        destination     = "/tmp/environment.xml"
    
        connection {
            type        = "ssh"
            user        = "centos"
            host        = "${element(openstack_networking_port_v2.thor_slave_port.*.all_fixed_ips.0, count.index)}"
            private_key = "${file(var.ssh_key_private)}"
            agent       = false
        }
    }
}

resource "openstack_compute_volume_attach_v2" "thor_support_attach" {
    count               = "${length(var.support_nodes)}"

    instance_id         = "${element(openstack_compute_instance_v2.thor_support.*.id, count.index)}"
    volume_id           = "${element(openstack_blockstorage_volume_v2.thor_support_volume.*.id, count.index)}"
    device              = "${var.device}"
}

resource "openstack_compute_volume_attach_v2" "thor_slave_attach" {
    count               = "${var.thor_slave_count}"

    instance_id         = "${element(openstack_compute_instance_v2.thor_slave.*.id, count.index)}"
    volume_id           = "${element(openstack_blockstorage_volume_v2.thor_slave_volume.*.id, count.index)}"
    device              = "${var.device}"
}

data "template_file" "thor_support_user_data" {
    count                       = "${length(var.support_nodes)}"

    template                    = "${file("${path.module}/files/provisioner-${var.image_name}.sh")}"
    vars = {
        hpcc_download_url       = "${var.hpcc_download_url}"
        hpcc_download_filename  = "${var.hpcc_download_filename}"
        device                  = "${var.device}"
        mountpoint              = "${var.mountpoint}"
        ip                      = "${element(openstack_networking_port_v2.thor_support_port.*.all_fixed_ips.0, count.index)}"
    }
}

data "template_file" "thor_slave_user_data" {
    count                       = "${var.thor_slave_count}"
    
    template                    = "${file("${path.module}/files/provisioner-${var.image_name}.sh")}"
    vars = {
        hpcc_download_url       = "${var.hpcc_download_url}"
        hpcc_download_filename  = "${var.hpcc_download_filename}"
        device                  = "${var.device}"
        mountpoint              = "${var.mountpoint}"
        ip                      = "${element(openstack_networking_port_v2.thor_slave_port.*.all_fixed_ips.0, count.index)}"
    }
}