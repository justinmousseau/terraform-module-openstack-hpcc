variable "device" {
    default = "/dev/vdb"
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

variable "thor_master_disk" {}

variable "thor_master_flavor_name" {}

variable "thor_slave_count" {}

variable "thor_slave_flavor_name" {}

variable "total_disk" {}