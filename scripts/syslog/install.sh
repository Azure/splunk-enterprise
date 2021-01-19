#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# Set script variables
SPLUNKHOME=/opt/splunkforwarder
SPLUNKLOCAL=$SPLUNKHOME/etc/system/local

# Option strings
SHORT=s:u:p:r:d:c:D:
LONG=splunk-uf-url:,splunk-user:,splunk-password:,role:,deployment-server:,conf-url:,dns-zone:

# Get options
OPTS=$(getopt --options $SHORT --long $LONG --name "$0" -- "$@")
if [ $? != 0 ] ; then echo "Failed to parse options...exiting." >&2 ; exit 1 ; fi
eval set -- "$OPTS"

# Set default values
SPLUNKUSER=splunkadmin

# Set variables 
while true ; do
  case "$1" in
    -s | --splunk-uf-url )
      SPLUNKUFURL="$2"
      shift 2
      ;;
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
echo "SPLUNKUFURL = $SPLUNKUFURL"
echo "SPLUNKUSER = $SPLUNKUSER"
echo "LICENSEURL = $LICENSEURL"
echo "ROLE = $ROLE"
echo "DSLB = $DSLB"
echo "CONFURL = $CONFURL"
echo "DNSZONE = $DNSZONE"

# Set common and role-specific URLs
COMMONCONFURL=$CONFURL/common
ROLECONFURL=$CONFURL/$ROLE

# RHEL firewall config
# Open required ports for Splunk
if test -f /etc/redhat-release; then
  firewall-cmd --zone=public --add-port=8000/tcp --permanent
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

# Download and extract Splunk Enterprise
wget -nv -O splunkforwarder.tgz "$SPLUNKUFURL"
tar xzf splunkforwarder.tgz -C /opt

# Download user-seed.conf
wget -nv -O $SPLUNKLOCAL/user-seed.conf "$COMMONCONFURL/etc/system/local/user-seed.conf"

# Create PW hash for writing to config
SPLUNKPWHASHED=$($SPLUNKHOME/bin/splunk hash-passwd $SPLUNKPW)

# Replace user and password placeholder tokens in user-seed.conf
echo HASHED_PASSWORD = "$SPLUNKPWHASHED" >> $SPLUNKLOCAL/user-seed.conf
sed -i "s/##SPLUNKUSER##/$SPLUNKUSER/g" $SPLUNKLOCAL/user-seed.conf

# Download deployment client configuration
wget -nv -O $SPLUNKLOCAL/deploymentclient.conf "$COMMONCONFURL/etc/system/local/deploymentclient.conf"
sed -i "s/##DSLB##/$DSLB/g" $SPLUNKLOCAL/deploymentclient.conf

# Download inputs.conf
wget -nv -O $SPLUNKLOCAL/inputs.conf "$ROLECONFURL/etc/system/local/inputs.conf"

# Create Splunk user
useradd -m splunk

# Set ownership for Splunk user
chown -R splunk:splunk /opt/splunkforwarder

# Enable boot start with systemd
$SPLUNKHOME/bin/splunk enable boot-start -systemd-managed 1 -user splunk --accept-license

# Download syslog-ng and start
echo "Installing syslog-ng...."
if test -f /etc/redhat-release; then
  if [[ $(cat /etc/redhat-release) == *"RedHat"* ]]; then
    subscription-manager repos --enable rhel-7-server-optional-rpms
  fi
  wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
  rpm -Uvh epel-release-latest-7.noarch.rpm
  cd /etc/yum.repos.d/
  wget https://copr.fedorainfracloud.org/coprs/czanik/syslog-ng321/repo/epel-7/czanik-syslog-ng321-epel-7.repo
  yum install syslog-ng -y
  yum install syslog-ng-http -y
  systemctl enable syslog-ng
  systemctl start syslog-ng
else
  wget -qO - http://download.opensuse.org/repositories/home:/laszlo_budai:/syslog-ng/xUbuntu_17.04/Release.key | sudo apt-key add -
  echo "deb http://download.opensuse.org/repositories/home:/laszlo_budai:/syslog-ng/xUbuntu_17.04 ./" > /etc/apt/sources.list.d/syslog-ng-obs.list
  apt-get update
  apt-get install syslog-ng -y
fi

echo "Adding catchall syslog-ng configuration..."
cat >> /etc/syslog-ng/syslog-ng.conf << EOL
# Custom syslog-ng configuration
options { create_dirs(yes); };
source s_remote { 
    tcp(ip(0.0.0.0) port(514));
    udp(ip(0.0.0.0) port(514)); 
};
destination d_catchall { file("/opt/log/remote/\${MONTH}-\${DAY}-\${HOUR}/\${FULLHOST}/catchall.log"); };
log { source(s_remote); destination(d_catchall); };
EOL

echo "Adding cron job to remove syslog messages after 7 days..."
cat >> /etc/cron.daily/remove-syslog-messages.sh << EOL
#!/bin/sh
find /opt/log/remote -name '*.log' -mtime +7 -exec rm -f {} \;
EOL

systemctl restart syslog-ng
systemctl status syslog-ng
