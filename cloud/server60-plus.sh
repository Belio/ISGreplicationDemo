#!/usr/bin/env bash

echo "Running server.sh"

adminUsername=$1
adminPassword=$2
services=$3
stackName=$4
version=$5
bucket=$6

echo "Got the parameters:"
echo adminUsername \'$adminUsername\'
echo adminPassword \'$adminPassword\'
echo services \'$services\'
echo stackName \'$stackName\'
echo version \'$version\'
echo bucket \'$bucket\'

#######################################################"
############## Install Couchbase Server ###############"
#######################################################"
echo "Installing Couchbase Server..."

wget https://packages.couchbase.com/releases/${version}/couchbase-server-enterprise-${version}-amzn2.x86_64.rpm
rpm --install couchbase-server-enterprise-${version}-amzn2.x86_64.rpm

source utilAmzLnx2.sh

echo "Turning off transparent huge pages"
turnOffTransparentHugepages

echo "Setting swappiness to 0..."
setSwappinessToZero

echo "Formatting disk"
formatDataDisk

yum -y update
yum -y install jq

if [ -z "$7" ]
then
  echo "This node is part of the autoscaling group that contains the rally point."
  rallyPublicDNS=`getRallyPublicDNS`
else
  rallyAutoScalingGroup=$7
  echo "This node is not the rally point and not part of the autoscaling group that contains the rally point."
  echo rallyAutoScalingGroup \'$rallyAutoScalingGroup\'
  rallyPublicDNS=`getRallyPublicDNS ${rallyAutoScalingGroup}`
fi

region=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document \
  | jq '.region'  \
  | sed 's/^"\(.*\)"$/\1/' )

instanceID=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document \
  | jq '.instanceId' \
  | sed 's/^"\(.*\)"$/\1/' )

nodePublicDNS=`curl http://169.254.169.254/latest/meta-data/public-hostname`

echo "Using the settings:"
echo adminUsername \'$adminUsername\'
echo adminPassword \'$adminPassword\'
echo services \'$services\'
echo stackName \'$stackName\'
echo rallyPublicDNS \'$rallyPublicDNS\'
echo region \'$region\'
echo instanceID \'$instanceID\'
echo nodePublicDNS \'$nodePublicDNS\'

if [[ ${rallyPublicDNS} == ${nodePublicDNS} ]]
then
  aws ec2 create-tags \
    --region ${region} \
    --resources ${instanceID} \
    --tags Key=Name,Value=${stackName}-ServerRally
else
  aws ec2 create-tags \
    --region ${region} \
    --resources ${instanceID} \
    --tags Key=Name,Value=${stackName}-Server
fi

cd /opt/couchbase
wget https://raw.githubusercontent.com/Belio/ISGreplicationDemo/main/stores.json
cd /opt/couchbase/bin/



echo "Running couchbase-cli node-init"
output=""
while [[ ! $output =~ "SUCCESS" ]]
do
  output=`./couchbase-cli node-init \
    --cluster=$nodePublicDNS \
    --node-init-hostname=$nodePublicDNS \
    --node-init-data-path=/mnt/datadisk/data \
    --node-init-index-path=/mnt/datadisk/index \
    -u=$adminUsername \
    -p=$adminPassword`
  echo node-init output \'$output\'
  sleep 10
done

if [[ $rallyPublicDNS == $nodePublicDNS ]]
then
  totalRAM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  dataRAM=$((40 * $totalRAM / 100000))
  indexRAM=$((8 * $totalRAM / 100000))
  analyticsRAM=$((1024 * 100000))

  echo "Running couchbase-cli cluster-init"
  ./couchbase-cli cluster-init \
    --cluster=$nodePublicDNS \
    --cluster-username=$adminUsername \
    --cluster-password=$adminPassword \
    --cluster-ramsize=$dataRAM \
    --index-storage-setting=memopt \
    --cluster-index-ramsize=$indexRAM \
    --cluster-analytics-ramsize=$analyticsRAM \
    --cluster-fts-ramsize=$indexRAM \
    --cluster-eventing-ramsize=$indexRAM \
    --services=${services}
else
  echo "Running couchbase-cli server-add"
  output=""
  while [[ $output != "Server $nodePublicDNS:8091 added" && ! $output =~ "Node is already part of cluster." ]]
  do
    output=`./couchbase-cli server-add \
      --cluster=$rallyPublicDNS \
      -u=$adminUsername \
      -p=$adminPassword \
      --server-add=$nodePublicDNS \
      --server-add-username=$adminUsername \
      --server-add-password=$adminPassword \
      --services=${services}`
    echo server-add output \'$output\'
    sleep 10
  done

  echo "Running couchbase-cli rebalance"
  output=""
  while [[ ! $output =~ "SUCCESS" ]]
  do
    output=`./couchbase-cli rebalance \
    --cluster=$rallyPublicDNS \
    -u=$adminUsername \
    -p=$adminPassword`
    echo rebalance output \'$output\'
    sleep 10
  done
fi

echo "Running couchbase-cli bucket-create"
output=""
while [[ ! $output =~ "SUCCESS" ]]
do
  output=`./couchbase-cli bucket-create \
    -c=$nodePublicDNS \
    --bucket-ramsize 256 \
    --username=$adminUsername \
    --bucket=$bucket \
    --bucket-type=couchbase \
    -p=$adminPassword`
  echo bucketcreate output \'$output\'
  sleep 10
done

echo "Setup RBAC"
output=""
while [[ ! $output =~ "SUCCESS" ]]
do
  output=`./couchbase-cli user-manage \
    -c $nodePublicDNS \
    --username $adminUsername \
    --password $adminPassword \
    --set --rbac-username admin --rbac-password $adminPassword --rbac-name adminrole \
    --roles bucket_full_access[*],bucket_admin[*] --auth-domain local`
  echo rbac output \'$output\'
  sleep 10
done

echo "import dataset"
output=""
while [[ ! $output =~ "imported" ]]
do
  output=`./cbimport json \
    --cluster $nodePublicDNS \
    --username "$adminUsername" \
    --bucket "$bucket" \
    --password "$adminPassword" \
    --format lines \
    --dataset file:///opt/couchbase/stores.json \
    --generate-key %_id% \
    --threads 4`
  echo node-init output \'$output\'
  sleep 10
done

echo "creating idx_stores_docType on stores"
curl \
  --use r "$adminUsername:$adminPassword" \
  --silent \
  --data-urlencode "statement=CREATE INDEX idx_stores_docType ON stores(docType)" \
  http://$nodePublicDNS:8093/query/service > /dev/null


echo "creating idx_stores_orderDate on stores"
curl \
  --user "$adminUsername:$adminPassword" \
  --silent \
  --data-urlencode "statement=CREATE INDEX idx_stores_orderDate ON stores(orderDate)" \
  http://$nodePublicDNS:8093/query/service > /dev/null

echo "creating idx_stores_price on stores"
curl \
  --user "$adminUsername:$adminPassword" \
  --silent \
  --data-urlencode "statement=CREATE INDEX idx_stores_price ON stores(price)" \
  http://$nodePublicDNS:8093/query/service > /dev/null

echo "creating idx_stores_order_region on stores"
curl \
  --user "$adminUsername:$adminPassword" \
  --silent \
  --data-urlencode "statement=CREATE INDEX idx_stores_order_region ON stores(billing.region)" \
  http://$nodePublicDNS:8093/query/service > /dev/null

