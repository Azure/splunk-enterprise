#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# Set script variables
SPLUNKHOME=/opt/splunk
SPLUNKLOCAL=$SPLUNKHOME/etc/system/local

# Parse command-line options

# Option strings
SHORT=U:u:p:r:l:d:c:D:i:h:I:v:P:s:R:S:H:C:n:f:N:
LONG=splunk-url:,splunk-user:,splunk-password:,role:,license-file:,deployment-server:,conf-url:,dns-zone:,indexer-count:,hf-pipelines:,indexer-pipelines:,vm-sku:,pass4symmkey:,site:,replication-factor:,search-factor:,deploy-hec:,sh-count:,sh-instance:,deploy-heavy-forwarders:,heavy-forwarder-count:

# Get options
OPTS=$(getopt --options $SHORT --long $LONG --name "$0" -- "$@")
if [ $? != 0 ] ; then echo "Failed to parse options...exiting." >&2 ; exit 1 ; fi
eval set -- "$OPTS"

# Set default values
SPLUNKUSER=splunkadmin


# Set variables 
while true ; do
  case "$1" in
    -U | --splunk-url )
      SPLUNKURL="$2"
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
    -l | --license-file )
      LICENSEFILE="$2"
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
    -i | --indexer-count )
      INDEXERCOUNT="$2"
      shift 2
      ;;
    -h | --hf-pipelines )
      HFPIPELINES="$2"
      shift 2
      ;;
    -I | --indexer-pipelines )
      INDEXERPIPELINES="$2"
      shift 2
      ;;
    -v | --vm-sku )
      VMSKU="$2"
      shift 2
      ;;
    -P | --pass4symmkey )
      PASS4SYMMKEY="$2"
      shift 2
      ;;
    -s | --site )
      SITE="$2"
      shift 2
      ;;
    -R | --replication-factor )
      REPLICATIONFACTOR="$2"
      shift 2
      ;;
    -S | --search-factor )
      SEARCHFACTOR="$2"
      shift 2
      ;;
    -H | --deploy-hec )
      DEPLOYHEC="$2"
      shift 2
      ;;
    -C | --sh-count )
      SHCOUNT="$2"
      shift 2
      ;;
    -n | --sh-instance )
      SHINSTANCE="$2"
      shift 2
      ;;
    -f | --deploy-heavy-forwarders )
      DEPLOYHFS="$2"
      shift 2
      ;;
    -N | --heavy-forwarder-count )
      HFCOUNT="$2"
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
echo "SPLUNKURL = $SPLUNKURL"
echo "SPLUNKUSER = $SPLUNKUSER"
echo "LICENSEFILE = $LICENSEFILE"
echo "ROLE = $ROLE"
echo "DSLB = $DSLB"
echo "CONFURL = $CONFURL"
echo "DNSZONE = $DNSZONE"
echo "INDEXERCOUNT = $INDEXERCOUNT"
echo "LICENSEMASTERHOST = $LICENSEMASTERHOST"
echo "HFPIPELINES = $HFPIPELINES"
echo "VMSKU = $VMSKU"
echo "INDEXERPIPELINES = $INDEXERPIPELINES"
echo "SITE = $SITE"
echo "REPLICATIONFACTOR = $REPLICATIONFACTOR"
echo "SEARCHFACTOR = $SEARCHFACTOR"
echo "DEPLOYHEC = $DEPLOYHEC"
echo "SHCOUNT = $SHCOUNT"
echo "SHINSTANCE = $SHINSTANCE"
echo "DEPLOYHFS = $DEPLOYHFS"
echo "HFCOUNT = $HFCOUNT"

# Set common and role-specific URLs
COMMONCONFURL=$CONFURL/common
ROLECONFURL=$CONFURL/$ROLE
MASTERAPPS=$SPLUNKHOME/etc/master-apps

# Construct common hostnames
LICENSEMASTERHOST=licensemaster.$DNSZONE
CLUSTERMASTERHOST=clustermaster.$DNSZONE
HOSTNAME=$(hostname).$DNSZONE
SHDEPLOYERHOST=shd.$DNSZONE

# RHEL firewall config
# Open required ports for Splunk
if test -f /etc/redhat-release; then
  firewall-cmd --zone=public --add-port=8000/tcp --permanent
  firewall-cmd --zone=public --add-port=8001/tcp --permanent
  firewall-cmd --zone=public --add-port=8002/tcp --permanent
  firewall-cmd --zone=public --add-port=8003/tcp --permanent
  firewall-cmd --zone=public --add-port=8089/tcp --permanent
  firewall-cmd --zone=public --add-port=9997/tcp --permanent
  firewall-cmd --zone=public --add-port=8181/tcp --permanent
  firewall-cmd --zone=public --add-port=8191/tcp --permanent
  firewall-cmd --reload
fi

# Disk config
# Disk configutation for all VMs
parted --script /dev/disk/azure/scsi1/lun0 mklabel gpt mkpart primary ext4 1MiB 100%
partprobe
sleep 10
mkfs.ext4 /dev/disk/azure/scsi1/lun0-part1
echo "/dev/disk/azure/scsi1/lun0-part1  /opt    ext4    defaults    0 2" >> /etc/fstab
mount -a

if [ "$ROLE" = "indexer" ]; then
# Additional disk configutation for indexer VMs
  parted --script /dev/disk/azure/scsi1/lun1 mklabel gpt mkpart primary ext4 1MiB 100%
  partprobe
  sleep 10
  mkfs.ext4 /dev/disk/azure/scsi1/lun1-part1
  mkdir -p /opt/splunkdata/cold
  echo "/dev/disk/azure/scsi1/lun1-part1  /opt/splunkdata/cold    ext4    defaults    0 2" >> /etc/fstab
  mount -a
  if [[ $VMSKU == *"_L"* ]]; then
      nvmecount=$(lsblk -l -d | grep -c nvme)
      nvmeloopcount=$(($nvmecount-1))
      
      for i in $(seq 0 $nvmeloopcount)
      do
          parted --script /dev/nvme"$i"n1 mklabel gpt mkpart primary ext4 1MiB 100%
      done

      partprobe
      sleep 10

      mdadm --create /dev/md0 --level=stripe --raid-devices=$nvmecount /dev/nvme[0-$nvmeloopcount]n1p1
      
      mkfs.ext4 /dev/md0
      mkdir -p /opt/splunkdata/hot
      echo "/dev/md0  /opt/splunkdata/hot    ext4    defaults    0 2" >> /etc/fstab
      mount -a
  else
      parted --script /dev/disk/azure/scsi1/lun2 mklabel gpt mkpart primary ext4 1MiB 100%
      partprobe
      sleep 10
      mkfs.ext4 /dev/disk/azure/scsi1/lun2-part1
      mkdir -p /opt/splunkdata/hot
      echo "/dev/disk/azure/scsi1/lun2-part1  /opt/splunkdata/hot    ext4    defaults    0 2" >> /etc/fstab
  mount -a
  fi

  cold_disk_size_kb=$(df -BM | grep "/opt/splunkdata/cold" | sed -r 's/\/dev\/[a-z0-9]+\s+([0-9]+)M\s+[0-9]+M\s+[0-9]+M\s+[0-9]+%\s+\/opt\/splunkdata\/cold/\1/')
  hot_disk_size_kb=$(df -BM | grep "/opt/splunkdata/hot" | sed -r 's/\/dev\/[a-z0-9]+\s+([0-9]+)M\s+[0-9]+M\s+[0-9]+M\s+[0-9]+%\s+\/opt\/splunkdata\/hot/\1/')
  splunk_cold_volume_size=$(($cold_disk_size_kb*95/100))
  splunk_hot_volume_size=$(($hot_disk_size_kb*95/100))
fi

# Download and extract Splunk Enterprise
wget -nv -O splunk.tgz "$SPLUNKURL"
tar xzf splunk.tgz -C /opt

# Fix systemd unit file for Splunk 7.3 as per https://docs.splunk.com/Documentation/Splunk/7.3.7/Admin/RunSplunkassystemdservice
OS=$(grep -oP '^NAME="\K[^"]+' /etc/os-release)
SPLUNKVER=$(grep -oP '^VERSION=\K\d.\d' /opt/splunk/etc/splunk.version)
if [[ $OS == "Ubuntu" ]]; then
  if [[ $SPLUNKVER == "7.3" ]]; then
    sed -i 's/\/init.scope//g' /etc/systemd/system/Splunkd.service
  fi
fi

# Download user-seed.conf and server.conf - applies to all Splunk instance roles
wget -nv -O $SPLUNKLOCAL/user-seed.conf "$COMMONCONFURL/etc/system/local/user-seed.conf"
wget -nv -O $SPLUNKLOCAL/server.conf "$ROLECONFURL/etc/system/local/server.conf"
wget -nv -O $SPLUNKLOCAL/web.conf "$ROLECONFURL/etc/system/local/web.conf"

# Create PW hash for writing to config
SPLUNKPWHASHED=$($SPLUNKHOME/bin/splunk hash-passwd $SPLUNKPW)

# Replace user and password placeholder tokens in user-seed.conf
echo HASHED_PASSWORD = "$SPLUNKPWHASHED" >> $SPLUNKLOCAL/user-seed.conf
sed -i "s/##SPLUNKUSER##/$SPLUNKUSER/g" $SPLUNKLOCAL/user-seed.conf

# Replace license master placeholder token in server.conf
sed -i "s/##LICENSEMASTERHOST##/$LICENSEMASTERHOST/g" $SPLUNKLOCAL/server.conf

# Replace AZ placeholder in server.conf 
sed -i "s/##SITE##/$SITE/g" $SPLUNKLOCAL/server.conf

# Replace cluster master host in server.conf
sed -i "s/##CLUSTERMASTERHOST##/$CLUSTERMASTERHOST/g" $SPLUNKLOCAL/server.conf

# Apply indexer and HF pipelines config via server.conf
sed -i "s/##HFPIPELINES##/$HFPIPELINES/g" $SPLUNKLOCAL/server.conf
sed -i "s/##INDEXERPIPELINES##/$INDEXERPIPELINES/g" $SPLUNKLOCAL/server.conf

# Replace pass4symmkey in server.conf
sed -i "s/##SECRET##/$PASS4SYMMKEY/g" $SPLUNKLOCAL/server.conf

# Replace local hostname in server.conf
sed -i "s/##HOSTNAME##/$HOSTNAME/g" $SPLUNKLOCAL/server.conf

# Construct indexer list for Deployment Server, Search Head Deployer and Heavy Forwarders
if [ "$ROLE" = "deployment-server" ] || [ "$ROLE" = "search-head-deployer" ] || [ "$ROLE" = "heavy-forwarder" ]; then
    INDEXERCOUNT=$(($INDEXERCOUNT - 1))
    INDEXERLIST=indexer0.$DNSZONE:9997
    if test $INDEXERCOUNT -gt 0; then
        for i in $( seq 1 $INDEXERCOUNT )
        do
            INDEXERLIST="$INDEXERLIST,indexer$i.$DNSZONE:9997"
        done
    fi
fi

# Create Splunk user
useradd -m splunk

# Role specific configuration
case "$ROLE" in
    cluster-master )
        wget -nv -O $MASTERAPPS/_cluster/local/indexes.conf "$ROLECONFURL/etc/master-apps/_cluster/local/indexes.conf"
        if [ $DEPLOYHEC = "True" ]; then
            echo "Configuring HTTP Event Collection..."
            mkdir $MASTERAPPS/httpeventconfig
            mkdir $MASTERAPPS/httpeventconfig/local
            wget -nv -O $MASTERAPPS/httpeventconfig/local/inputs.conf "$ROLECONFURL/etc/master-apps/httpeventconfig/local/inputs.conf"
            TOKEN=$(uuidgen)
            sed -i "s/##TOKEN##/$TOKEN/g" $MASTERAPPS/httpeventconfig/local/inputs.conf
        else
            echo "HTTP Event Collection not required, continuing..."
        fi
        SITEREPLICATIONFACTOR=$(($REPLICATIONFACTOR/3))
        SITESEARCHFACTOR=$(($SEARCHFACTOR/3))

        if [ $SITEREPLICATIONFACTOR = "0" ]; then
            sed -i "s/##REPLICATIONFACTOR##/site_replication_factor = origin:1,total:$REPLICATIONFACTOR/g" $SPLUNKLOCAL/server.conf
        else
            sed -i "s/##REPLICATIONFACTOR##/site_replication_factor = origin:1,site1:$SITEREPLICATIONFACTOR,site2:$SITEREPLICATIONFACTOR,site2:$SITEREPLICATIONFACTOR,total:$REPLICATIONFACTOR/g" $SPLUNKLOCAL/server.conf 
        fi

        if [ $SITESEARCHFACTOR = "0" ]; then
            sed -i "s/##SEARCHFACTOR##/site_search_factor = origin:1,total:$SEARCHFACTOR/g" $SPLUNKLOCAL/server.conf
        else
            sed -i "s/##SEARCHFACTOR##/site_search_factor = origin:1,site1:$SITESEARCHFACTOR,site2:$SITESEARCHFACTOR,site2:$SITESEARCHFACTOR,total:$SEARCHFACTOR/g" $SPLUNKLOCAL/server.conf 
        fi
        ;;
    indexer )
        wget -nv -O $SPLUNKLOCAL/inputs.conf "$COMMONCONFURL/etc/system/local/inputs.conf"
        wget -nv -O $SPLUNKLOCAL/indexes.conf "$ROLECONFURL/etc/system/local/indexes.conf"
        sed -i "s/##HOTWARMSIZEMB##/$splunk_hot_volume_size/g" $SPLUNKLOCAL/indexes.conf
        sed -i "s/##COLDSIZEMB##/$splunk_cold_volume_size/g" $SPLUNKLOCAL/indexes.conf
        chown -R splunk:splunk /opt/splunkdata
        ;;
    search-head )
        ;;
    deployment-server )
        wget -nv -O $SPLUNKLOCAL/outputs.conf "$COMMONCONFURL/etc/system/local/outputs.conf"
        sed -i "s/##SERVERLIST##/$INDEXERLIST/g" $SPLUNKLOCAL/outputs.conf
        wget -nv -O $SPLUNKLOCAL/serverclass.conf "$ROLECONFURL/etc/system/local/serverclass.conf"
        mkdir -p $SPLUNKHOME/etc/deployment-apps/default_outputs/local
        cp $SPLUNKLOCAL/outputs.conf "$SPLUNKHOME/etc/deployment-apps/default_outputs/local/outputs.conf"
        ;;
    license-master )
        mkdir -p $SPLUNKHOME/etc/licenses/enterprise
        echo $LICENSEFILE | base64 -di > $SPLUNKHOME/etc/licenses/enterprise/Splunk.License.lic
        ;;
    search-head-deployer )
        mkdir -p $SPLUNKHOME/etc/shcluster/apps/default_outputs/local
        wget -nv -O $SPLUNKHOME/etc/shcluster/apps/default_outputs/local/outputs.conf "$COMMONCONFURL/etc/system/local/outputs.conf"
        sed -i "s/##SERVERLIST##/$INDEXERLIST/g" $SPLUNKHOME/etc/shcluster/apps/default_outputs/local/outputs.conf
        ;;
    heavy-forwarder )
        wget -nv -O $SPLUNKLOCAL/inputs.conf "$COMMONCONFURL/etc/system/local/inputs.conf"
        wget -nv -O $SPLUNKLOCAL/outputs.conf "$COMMONCONFURL/etc/system/local/outputs.conf"
        sed -i "s/##SERVERLIST##/$INDEXERLIST/g" $SPLUNKLOCAL/outputs.conf
        ;;
   esac

# Deployment client configuration
case "$ROLE" in

   # Ignore non-applicable roles
    indexer )
        ;;
    search-head )
        ;;
    deployment-server )
        ;;
    *)
        wget -nv -O $SPLUNKLOCAL/deploymentclient.conf "$COMMONCONFURL/etc/system/local/deploymentclient.conf"
        sed -i "s/##DSLB##/$DSLB/g" $SPLUNKLOCAL/deploymentclient.conf
        ;;
   esac

# Set ownership for Splunk user
chown -R splunk:splunk /opt/splunk

# Enable boot start with systemd
$SPLUNKHOME/bin/splunk enable boot-start -systemd-managed 1 -user splunk --accept-license

# Download systemd unit file to disable transparent huge pages
wget -nv -O /etc/systemd/system/disable-thp.service "$COMMONCONFURL/disable-thp.service"

# Disable THP
systemctl daemon-reload
systemctl enable disable-thp
systemctl start disable-thp

#Start Splunk
$SPLUNKHOME/bin/splunk start || true

# Post install steps
case "$ROLE" in
  search-head )
    SHCOUNT=$(($SHCOUNT - 1))
    if test $SHINSTANCE -eq 0
    then
      sleep 60
      SHLIST=https://`hostname`.$DNSZONE:8089
      for i in $( seq 0 $SHCOUNT )
      do
        if test $i -ne 0
        then
          SHLIST="$SHLIST,https://sh$i.$DNSZONE:8089"
        fi
        until curl -s https://sh$i.$DNSZONE:8089 --insecure >/dev/null
        do
          sleep 15
        done
      done
      sudo -iu splunk $SPLUNKHOME/bin/splunk bootstrap shcluster-captain -servers_list "$SHLIST" -auth $SPLUNKUSER:$SPLUNKPW
    fi
    ;;
  search-head-deployer )
    SHCOUNT=$(($SHCOUNT - 1))
    # Check if SHs are in the cluster
    for i in $( seq 0 $SHCOUNT )
      do
        until curl -s -u $SPLUNKUSER:$SPLUNKPW https://sh$i.$DNSZONE:8089/services/shcluster/member/members --insecure >/dev/null
          do
            echo "Search Head sh$i.$DNSZONE is not part of the Search Head Cluster yet..."
            sleep 30
          done
        echo "sh$i.$DNSZONE is now part of the cluster, continuing..."
      done

    until sudo -iu splunk $SPLUNKHOME/bin/splunk apply shcluster-bundle -target https://sh0.$DNSZONE:8089 -auth $SPLUNKUSER:$SPLUNKPW --answer-yes
      do
        echo "Waiting on Search Head Cluster to be available to apply bundle..."
        sleep 60
      done
    echo "Search Head Cluster bundle applied"
    ;;
  monitoring-console )
    until curl -s https://localhost:8089 --insecure >/dev/null
    do
        echo "Waiting for local Splunk to be available..."
        sleep 15
    done

    #Add Search Peers
    until curl -s https://$LICENSEMASTERHOST:8089 --insecure >/dev/null
    do
        echo "Waiting for License Master to be available..."
        sleep 15
    done
    $SPLUNKHOME/bin/splunk add search-server https://$LICENSEMASTERHOST:8089 -auth $SPLUNKUSER:$SPLUNKPW -remoteUsername $SPLUNKUSER -remotePassword $SPLUNKPW

    until curl -s https://$CLUSTERMASTERHOST:8089 --insecure >/dev/null
    do
        echo "Waiting for Cluster Master to be available..."
        sleep 15
    done
    $SPLUNKHOME/bin/splunk add search-server https://$CLUSTERMASTERHOST:8089 -auth $SPLUNKUSER:$SPLUNKPW -remoteUsername $SPLUNKUSER -remotePassword $SPLUNKPW

    until curl -s https://$SHDEPLOYERHOST:8089 --insecure >/dev/null
    do
        echo "Waiting for Search Head Deployer to be available..."
        sleep 15
    done
    $SPLUNKHOME/bin/splunk add search-server https://$SHDEPLOYERHOST:8089 -auth $SPLUNKUSER:$SPLUNKPW -remoteUsername $SPLUNKUSER -remotePassword $SPLUNKPW

    if [[ "$DEPLOYHFS" == "True" ]]; then
      HFCOUNT=$(($HFCOUNT - 1))
      for i in $( seq 0 $HFCOUNT )
        do
          until curl -s https://hf$i.$DNSZONE:8089 --insecure >/dev/null
          do
            echo "Waiting for Heavy Forwarder $i to be available..."
            sleep 15
          done
          $SPLUNKHOME/bin/splunk add search-server https://hf$i.$DNSZONE:8089 -auth $SPLUNKUSER:$SPLUNKPW -remoteUsername $SPLUNKUSER -remotePassword $SPLUNKPW
      done
    fi

    until curl -s https://ds0.$DNSZONE:8089 --insecure >/dev/null
    do
        echo "Waiting for Deployment Server to be available..."
        sleep 15
    done
    $SPLUNKHOME/bin/splunk add search-server https://ds0.$DNSZONE:8089 -auth $SPLUNKUSER:$SPLUNKPW -remoteUsername $SPLUNKUSER -remotePassword $SPLUNKPW

    SHCOUNT=$(($SHCOUNT - 1))
    # Check if SHs are in the cluster
    for i in $( seq 0 $SHCOUNT )
      do
        until curl -s -u $SPLUNKUSER:$SPLUNKPW https://sh$i.$DNSZONE:8089/services/shcluster/member/members --insecure >/dev/null
          do
            echo "Search Head sh$i.$DNSZONE is not part of the Search Head Cluster yet..."
            sleep 30
          done
        echo "sh$i.$DNSZONE is now part of the cluster, continuing..."
        $SPLUNKHOME/bin/splunk add search-server https://sh$i.$DNSZONE:8089 -auth $SPLUNKUSER:$SPLUNKPW -remoteUsername $SPLUNKUSER -remotePassword $SPLUNKPW
      done

    sed -E -i '/./{H;$!d} ; x ; s/(\[distributedSearch:dmc_group_indexer\][\r\n]+servers = )localhost:localhost,/\1/' $SPLUNKHOME/etc/system/local/distsearch.conf
    sed -E -i '/./{H;$!d} ; x ; s/(\[distributedSearch:dmc_group_license_master\][\r\n]+servers = )localhost:localhost,/\1/' $SPLUNKHOME/etc/system/local/distsearch.conf

    $SPLUNKHOME/bin/splunk restart
    ;;
esac