#!/usr/bin/env bash
#create aws env (remote sync gw)
echo "enter the stack name"
read stackName
echo "creating remote sync gateway and loading the data"
sh cloud/deploy.sh $stackName

#waiting for remote sync gw to be up and running...
echo "waiting for remote sync gw to be created..."

REGION=`aws configure get region`
instanceId=""
while [[ ! $instanceIdSync =~ "i-" ]]
do
instanceIdSync=$(aws autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[?contains(Tags[?Key==`aws:cloudformation:logical-id`].Value, `SyncGatewayAutoScalingGroup`)]' --filters Name=tag-value,Values=${stackName} --region ${REGION} \
| grep -i instanceid | awk '{ print $2}' | sed -e 's/"//g' | cut -d',' -f1)
echo "waiting for instance creation on aws ..."
sleep 10
done
echo "instance id is $instanceIdSync"
echo "finding IP"
ipAddress=$(aws ec2 describe-instances --instance-ids ${instanceIdSync} --region ${REGION} | grep -i PublicIpAddress | awk '{ print $2 }' | head -1 | cut -d"," -f1 | sed -e 's/"//g')
echo "remote ipaddress is "\'$ipAddress\'
#verify sync gateway is up
echo "verify remote sync gateway is up and running"
url=http://$ipAddress:4985/stores
echo "complete url is $url"
until $(curl --output /dev/null --head --fail --silent $url); do
        printf 'waiting for remote sync gw to be up...\n'
        sleep 20
done

echo "starting docker compose"
export REMOTEIP=$ipAddress
echo "remote ip is $REMOTEIP"
docker compose stop
docker compose rm -f
docker rmi couchbase/sync-gateway
docker-compose up -d