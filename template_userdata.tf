data "template_file" "thor_master_user_data" {
    template                    = "${file("${path.module}/provisioner.sh")}"
    vars = {
        hpcc_download_url       = "${var.hpcc_download_url}"
        hpcc_download_filename  = "${var.hpcc_download_filename}"
        device                  = "${var.device}"
        mountpoint              = "${var.mountpoint}"
        ip                      = "${openstack_networking_port_v2.thor_master_port.all_fixed_ips.0}"
    }
}

data "template_file" "thor_slave_user_data" {
    count                       = "${var.thor_slave_count}"
    
    template                    = "${file("${path.module}/provisioner.sh")}"
    vars = {
        hpcc_download_url       = "${var.hpcc_download_url}"
        hpcc_download_filename  = "${var.hpcc_download_filename}"
        device                  = "${var.device}"
        mountpoint              = "${var.mountpoint}"
        ip                      = "${element(openstack_networking_port_v2.thor_slave_port.*.all_fixed_ips.0, count.index)}"
    }
}