#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

set -x

# Set script variables
SPLUNKHOME=/opt/splunkforwarder
SPLUNKLOCAL=$SPLUNKHOME/etc/system/local

# Option strings
SHORT=s:u:p:r:d:c:D:h:t
LONG=splunk-uf-url:,splunk-user:,splunk-password:,role:,deployment-server:,conf-url:,dns-zone:,hec-lb:,hec-token:

# Get options
OPTS=$(getopt --options $SHORT --long $LONG --name "$0" -- "$@")
if [ $? != 0 ] ; then echo "Failed to parse options...exiting." >&2 ; exit 1 ; fi
eval set -- "$OPTS"

# Set default values
SPLUNKUSER=splunkadmin

# Set variables 
while true ; do
  case "$1" in
    -u | --splunk-user )
      SPLUNKUSER="$2"
      shift 2
      ;;
    -p | --splunk-password )
      SPLUNKPW="$2"
      shift 2
      ;;
    -r | --role )
      ROLE="$2"
      shift 2
      ;;
    -d | --deployment-server )
      DSLB="$2"
      shift 2
      ;;
    -c | --conf-url )
      CONFURL="$2"
      shift 2
      ;;
    -D | --dns-zone )
      DNSZONE="$2"
      shift 2
      ;;
    -h | --hec-lb )
      HECLB="$2"
      shift 2
      ;;
    -t | --hec-token )
      HECTOKEN="$2"
      shift 2
      ;;
    -- )
      shift
      break
      ;;
    *)
      echo "Internal error!"
      exit 1
      ;;
  esac
done

# Print the variables
echo "SPLUNKUSER = $SPLUNKUSER"
echo "LICENSEURL = $LICENSEURL"
echo "ROLE = $ROLE"
echo "DSLB = $DSLB"
echo "CONFURL = $CONFURL"
echo "DNSZONE = $DNSZONE"
echo "HECLB = $HECLB"
echo "HECTOKEN = $HECTOKEN"

# Set role-specific URLs
ROLECONFURL=$CONFURL/$ROLE

# RHEL firewall config
# Open required ports for Splunk
if test -f /etc/redhat-release; then
  firewall-cmd --zone=public --add-port=8089/tcp --permanent
  firewall-cmd --zone=public --add-port=9997/tcp --permanent
  firewall-cmd --zone=public --add-port=514/tcp --permanent
  firewall-cmd --reload
fi

# Disk config
parted --script /dev/disk/azure/scsi1/lun0 mklabel gpt mkpart primary ext4 1MiB 100%
partprobe
sleep 10
mkfs.ext4 /dev/disk/azure/scsi1/lun0-part1
echo "/dev/disk/azure/scsi1/lun0-part1  /opt    ext4    defaults    0 2" >> /etc/fstab
mount -a

## Download Splunk Connect for Syslog and start
echo "Installing Docker"
if test -f /etc/redhat-release; then
  if [[ $(cat /etc/redhat-release) == *"Red Hat"* ]]; then
    sudo rm -rf /etc/yum/vars/releasever
    sudo yum -y --disablerepo='*' remove 'rhui-azure-rhel7-eus'
    sudo yum -y --config='https://rhelimage.blob.core.windows.net/repositories/rhui-microsoft-azure-rhel7.config' install 'rhui-azure-rhel7'
  fi
  sudo yum -y remove docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine
  sudo yum -y install -y yum-utils
  sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  sudo yum -y install docker-ce docker-ce-cli containerd.io
  sudo systemctl start docker
  echo "Verifying that docker is installed correctly..."
  sudo docker run hello-world
else
  sudo apt-get -y remove docker docker-engine docker.io containerd runc
  sudo apt-get -y update
  sudo apt-get -y install apt-transport-https ca-certificates curl gnupg lsb-release
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get -y update
  sudo apt-get -y install docker-ce docker-ce-cli containerd.io
  echo "Verifying that docker is installed correctly..."
  sudo docker run hello-world
fi

echo "Updating receive buffer sizes..."
sudo sysctl --write net.core.rmem_default=17039360
sudo sysctl --write net.core.rmem_max=17039360

wget -nv -O /lib/systemd/system/sc4s.service "$ROLECONFURL/sc4s.service"

sudo docker volume create splunk-sc4s-var
mkdir -p /opt/sc4s/local /opt/sc4s/archive /opt/sc4s/tls

wget -nv -O /opt/sc4s/env_file "$ROLECONFURL/env_file"
sed -i "s/##HECLB##/$HECLB/g" /opt/sc4s/env_file
sed -i "s/##HECTOKEN##/$HECTOKEN/g" /opt/sc4s/env_file

sudo systemctl daemon-reload
sudo systemctl enable sc4s
sleep 5
sudo systemctl start sc4s
