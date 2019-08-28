variable "device" {
    default = "/dev/vdb"
}

variable "environment_filename" {
    default = ""
}

variable "mountpoint" {
    default = "/mnt/vdb"
}

variable "ssh_key_private" {
    default = "~/.ssh/id_rsa"
}

variable "ssh_key_public" {
    default = "~/.ssh/id_rsa.pub"
}

variable "hpcc_download_filename" {}

variable "hpcc_download_url" {}

variable "image_name" {}

variable "network_name" {}

variable "subnet_name" {}

variable "thor_slave_count" {}

variable "thor_slave_flavor_name" {}

variable "thor_slave_total_disk" {}

variable "support_nodes" {}

variable "zeppelin_download_filename" {}

variable "zeppelin_download_url" {}

variable "zeppelin_hash_url" {}