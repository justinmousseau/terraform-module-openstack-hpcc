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
    # This block is necessary to prevent provisioner from contiuing before volume is attached
    while [ ! -b ${device} ]; do sleep 1; done

    # Create the mountpoint. By default, this is /mnt/vdb/
    mkdir -p ${mountpoint}

    # To avoid deleting files from existing volumes, we will first Check to see if volume is formatted
    FS_UUID=$(lsblk -no UUID ${device})
    echo "Testing if volume ${device} is formatted"
    if [[ $FS_UUID = "" ]]
    then
        echo "Volume not formatted. Formatting ${device}"
        mkfs.xfs ${device}
        sleep 5
    fi

    # Add volume to /etc/fstab
    grep ${mountpoint} /etc/fstab
    if [ $? -ne 0 ]
    then
        echo "Add ${device} to /etc/fstab"
        FS_UUID=$(lsblk -no UUID ${device})
        echo "UUID=$FS_UUID ${mountpoint}    xfs    noatime    0 0" >> /etc/fstab
    fi

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
cp /home/centos/RPM-GPG-KEY-EPEL-7 /etc/pki/rpm-gpg

yum update -y

# Install Java
yum install java-1.8.0-openjdk -y

# Create JAVA_HOME and JRE_HOME environment variables
JAVA_PATH=$(readlink -f $(which java) | sed 's|/jre/bin/java||')

printf "%s\n" \
    "#!/bin/sh" \
    "export JAVA_HOME=$${JAVA_PATH}" \
    "export JRE_HOME=$${JAVA_PATH}/jre" \
    "export PATH=$PATH:$${JAVA_PATH}/bin:$${JAVA_PATH}/jre/bin" > /etc/profile.d/java_home.sh

printf "%s\n" \
    "export JAVA_HOME=$${JAVA_PATH}" \
    "export JRE_HOME=$${JAVA_PATH}/jre" \
    "export PATH=$PATH:$${JAVA_PATH}/bin:$${JAVA_PATH}/jre/bin" >> /home/centos/.bash_profile

# ---
# Install HPCC
# ---

# Download package and md5sum
wget -a /var/log/wget.log -P /tmp ${hpcc_download_url}/${hpcc_download_filename}
wget -a /var/log/wget.log -P /tmp ${hpcc_download_url}/${hpcc_download_filename}.md5

# Compare checksum
A=$(md5sum /tmp/${hpcc_download_filename} | awk '{print $1}')
B=$(cat /tmp/${hpcc_download_filename}.md5 | awk '{print $1}')

if [[ $A = $B ]]
then
    yum install /tmp/${hpcc_download_filename} -y

    # Create environment.xml file
    IP_NODE="$(cut -d '.' -f 4 <<< "${first_ip}")"

    /opt/HPCCSystems/sbin/envgen2 \
        -env-out /etc/HPCCSystems/environment.xml \
        -ip ${first_ip}-$(($IP_NODE + ${support_count} + ${thor_count} - 1)) \
        -supportnodes ${support_count} \
        -thornodes ${thor_count}
fi

# ---
# Install Zeppelin
# ---

if [[ `hostname -s` = "thor-support-01" && "${zeppelin_version}" != "" ]]
then

    PROXY=bdmzproxyout.risk.regn.net:80

    ZEPPELIN_DOWNLOAD_FILENAME=${zeppelin_version}-bin-all.tgz
    ZEPPELIN_DOWNLOAD_URL=${zeppelin_download_url}/${zeppelin_version}
    ZEPPELIN_HASH_URL=${zeppelin_hash_url}/${zeppelin_version}

    wget -e http_proxy=$PROXY -a /var/log/wget.log -P /tmp $ZEPPELIN_DOWNLOAD_URL/$ZEPPELIN_DOWNLOAD_FILENAME
    wget -e http_proxy=$PROXY -a /var/log/wget.log -P /tmp $ZEPPELIN_HASH_URL/$ZEPPELIN_DOWNLOAD_FILENAME.sha512

    # Compare checksum
    A=$(sha512sum /tmp/$ZEPPELIN_DOWNLOAD_FILENAME | awk '{print $1}')
    B=$(cat /tmp/$ZEPPELIN_DOWNLOAD_FILENAME.sha512 | awk '{print $1}')

    if [[ $A = $B ]]
    then

        # Install Zeppelin
        tar xf /tmp/$ZEPPELIN_DOWNLOAD_FILENAME -C /opt
        mv /opt/zeppelin-*-bin-all /opt/zeppelin

        # Configure Systemd service
        adduser -d /opt/zeppelin -s /sbin/nologin zeppelin
        chown -R zeppelin:zeppelin /opt/zeppelin
        
        printf "%s\n" \
            "[Unit]" \
            "Description=Zeppelin service" \
            "After=syslog.target network.target" \
            "" \
            "[Service]" \
            "Type=forking" \
            "ExecStart=/opt/zeppelin/bin/zeppelin-daemon.sh start" \
            "ExecStop=/opt/zeppelin/bin/zeppelin-daemon.sh stop" \
            "ExecReload=/opt/zeppelin/bin/zeppelin-daemon.sh reload" \
            "User=zeppelin" \
            "Group=zeppelin" \
            "Restart=always" \
            "" \
            "[Install]" \
            "WantedBy=multi-user.target" > /etc/systemd/system/zeppelin.service
        
        systemctl start zeppelin
        systemctl enable zeppelin
        systemctl status zeppelin

    fi

fi

# ---
# Start cluster
# ---

/opt/HPCCSystems/sbin/hpcc-run.sh -a hpcc-init start

echo "Provisioning complete!"
exit 0
