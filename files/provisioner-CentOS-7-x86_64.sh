#!/bin/bash -x

# ---
# Create log for provisioning script and output stdout and stderr to it
# ---

LOG=/var/log/provision.log
exec >$LOG 2>&1 # write stdout and stderr to logfile
set -x

# ---
# Format and mount filesystems
# ---

mount | grep ${device}
if [ $? -eq 0 ]
then
    echo "${device} was already mounted"
else
    echo "Format ${device}"

    # This block is necessary to prevent provisioner from contiuing before volume is attached
    while [ ! -b ${device} ]; do sleep 1; done

    mkfs.xfs ${device}
    mkdir -p ${mountpoint}
    
    sleep 5

    grep ${mountpoint} /etc/fstab
    if [ $? -ne 0 ]
    then
        echo "Add ${device} to /etc/fstab"
        FS_UUID=$(lsblk -no UUID ${device})
        echo "UUID=$FS_UUID ${mountpoint}    xfs    noatime    0 0" >> /etc/fstab
    fi

    echo "Mount ${device}"
    mount ${mountpoint}
fi

df -h

# ---
# Add hostname to /etc/hosts
# ---

grep `hostname` /etc/hosts
if [ $? -ne 0 ]
then
    echo "Add hostname and ip to /etc/hosts"
    echo "${ip} `hostname -s` `hostname`" >> /etc/hosts
fi

# ---
# Move directories from bootdisk to mountpoint
# ---

move_dir () {
    if [ ! -d ${mountpoint}$1 ] # if directory doesn't exist on the mounted volume
    then
        mkdir -p ${mountpoint}$1
        if [ -d $1 ] # if directory exists on root volume
        then
            mv $1 ${mountpoint}$(dirname "$1")
        fi
        ln -s ${mountpoint}$1 $1
    fi
}

# move_dir /usr/local
# move_dir /opt
move_dir /var/lib/HPCCSystems
move_dir /var/log/HPCCSystems

# ---
# Install dependencies
# ---

# Enable EPEL
sed -i '/LN-epel/,/enabled=0/ s/enabled=0/enabled=1/' /etc/yum.repos.d/LexisNexis.repo

# Copy RPM-GPG-KEY for EPEL-7 into /etc/pki/rpm-gpg
cp /etc/pki/rpm-gpg/files/RPM-GPG-KEY-EPEL-7 /etc/pki/rpm-gpg

yum update -y

# ---
# Install HPCC
# ---

# Download package and md5sum
wget -a /var/log/wget.log -P /tmp ${hpcc_download_url}${hpcc_download_filename}
wget -a /var/log/wget.log -P /tmp ${hpcc_download_url}${hpcc_download_filename}.md5

# Compare checksum
A=$(md5sum /tmp/${hpcc_download_filename} | awk '{print $1}')
B=$(cat /tmp/${hpcc_download_filename}.md5 | awk '{print $1}')

if [[ $A = $B ]]
then
    yum install "/tmp/"${hpcc_download_filename} -y

    # We must update the /etc/pam.d/su file to skip calling system-auth for user hpcc at session level
    # otherwise hpcc-init takes too long to execute waiting for timeout with each su call
    sed -i '0,/session/ s//session         [success=ignore default=1] pam_succeed_if.so user = hpcc\nsession         sufficient      pam_unix.so\nsession/' /etc/pam.d/su

    if [[ $(< /tmp/environment.xml) != " " ]] 
    then
        mv /tmp/environment.xml /etc/HPCCSystems/
        chown hpcc:hpcc /etc/HPCCSystems/environment.xml
        /etc/init.d/hpcc-init start
    fi

    echo "Provisioning complete!"
fi