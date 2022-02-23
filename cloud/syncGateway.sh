#!/bin/bash

echo "Running syncGateway.sh"

stackName=$1
version=$2

echo "Got the parameters:"
echo stackName \'$stackName\'
echo version \'$version\'

echo "Installing Couchbase Sync Gateway..."
wget https://packages.couchbase.com/releases/couchbase-sync-gateway/${version}/couchbase-sync-gateway-enterprise_${version}_x86_64.rpm
rpm --install couchbase-sync-gateway-enterprise_${version}_x86_64.rpm

yum -y install jq
rm -fr /usr/bin/aws
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install --update
. ~/.bash_profile

region=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document \
  | jq '.region'  \
  | sed 's/^"\(.*\)"$/\1/' )

instanceID=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document \
  | jq '.instanceId' \
  | sed 's/^"\(.*\)"$/\1/' )

echo "Using the settings:"
echo stackName \'$stackName\'
echo region \'$region\'
echo instanceID \'$instanceID\'

aws ec2 create-tags \
   --tags Key=region,Value=${region} \
  --resources ${instanceID} 

aws ec2 create-tags \
    --region ${region} \
    --resources ${instanceID} \
    --tags Key=Name,Value=${stackName}-SyncGateway

echo "Finding instanceid"
instanceId=""
while [[ ! $instanceIdServer =~ "i-" ]]
do
instanceIdServer=$(aws autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[?contains(Tags[?Key==`aws:cloudformation:logical-id`].Value, `ServerAutoScalingGroup`)]' --filters Name=tag-value,Values=${stackName} --region ${region} \
| grep -i instanceid | awk '{ print $2}' | sed -e 's/"//g' | cut -d',' -f1)
echo "instanceIdServer is"  \'$instanceIdServer\'
sleep 10
done
echo "finding IP"
ipAddress=$(aws ec2 describe-instances --instance-ids ${instanceIdServer} --region ${region} | grep -i PrivateIpAddress | awk '{ print $2 }' | head -1 | cut -d"," -f1 | sed -e 's/"//g')
echo "ipaddress is "\'$ipAddress\'

ip=http://$ipAddress:8091
echo "wait for cluster to be ready on ip " \'$ip\'
# wait for service to come up
until $(curl --output /dev/null --head --fail $ip); do
        printf '.'
        sleep 1
done
echo "cluster is up"

file="/opt/sync_gateway/etc/sync_gateway.json"
echo '
{
  "interface":":4984",
  "adminInterface":":4985",
  "metricsInterface":":4986",
  "log": ["*"],
  "logging": {
    "log_file_path": "/var/tmp/sglogs",
    "console": {
      "log_level": "debug",
      "log_keys": ["*"]
    },
    "error": {
      "enabled": true,
      "rotation": {
        "max_size": 20,
        "max_age": 180
      }
    },
    "warn": {
      "enabled": true,
      "rotation": {
        "max_size": 20,
        "max_age": 90
      }
    },
    "info": {
      "enabled": false
    },
    "debug": {
      "enabled": true
    }
  },
  "databases": {
    "stores": {
      "import_docs": true,
      "bucket":"stores",
      "server": "couchbase://'$ipAddress'",
      "enable_shared_bucket_access":true,
      "delta_sync": {
        "enabled":false
      },
      "import_filter": `
        function(doc) {
          return true;
        }
        `,
      "username": "admin",
      "password": "password",
      "users":{
          "admin": {"password": "password", "admin_channels": ["*"]},
          "store1": {"password": "password", "admin_channels":["channel:product.storeId.1","channel:order.storeId.1","channel:common"]}
      },
    "num_index_replicas":0,
    "sync": `
    function sync(doc, oldDoc) {
      /* sanity check */
      // check if document was removed from server or via SDK
      // In this case, just return
      if (isRemoved()) {
        return;
      }

      /* Routing */
      // Add doc to the users channel.
      if (doc.docType == "Order") {
          channel("channel:order."+doc.storeId)
      }
      else if (doc.docType == "Product") {
          channel("channel:product."+doc.storeId)
          console.log("*****->product channel");
      }
      else {
          channel("channel:common");
          console.log("*****->common channel");
      }

      // This is when document is removed via SDK or directly on server
      function isRemoved() {
        return( isDelete() && oldDoc == null);
      }

      function isDelete() {
        return (doc._deleted == true);
      }
      
    }
      `
    }
  }
}
' > ${file}
chmod 755 ${file}
chown sync_gateway ${file}
chgrp sync_gateway ${file}
# Need to restart to load the changes
sleep 40

echo "stop sync gateway"
sync_gateway_pid=$(ps -ef | grep sync_gateway | awk 'NR==2{print $2}')
kill $sync_gateway_pid
sleep 60
echo "start sync gateway"
service sync_gateway start