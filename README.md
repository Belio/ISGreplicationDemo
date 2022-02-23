# Couchbase Inter-Sync Gateway Replication Demo
This demo will be demonstrate how to configure Inter Sync Gateway replication.

This demo will deploy:
- one node sync gateway + one node couchbase server on AWS
- two nodes sync gateway + one node couchbase server locally through docker compose

On the remote sync gateway some sample data (see stores.json) will be automatically loaded in Couchbase Server by the startup script.
On the local sync gateway replica will be configured through JSON configuration: one for the common channel in pull and one for the store channel pushAndPull (bidirectional) 


To run it:

1) aws cli must be installed (https://aws.amazon.com/cli/)
2) f you don't have a key, you'll also need to create one. That can be done with these commands:

REGION=`aws configure get region`
KEY_NAME="couchbase-${REGION}"
KEY_FILENAME=~/.ssh/${KEY_NAME}.pem
aws ec2 create-key-pair \
  --region ${REGION} \
  --key-name ${KEY_NAME} \
  --query 'KeyMaterial' \
  --output text > ${KEY_FILENAME}
chmod 600 ${KEY_FILENAME}
echo "Key saved to ${KEY_FILENAME}"

3) launch sh startup.sh and choose a stack name (it is just the name of the stack to be deployed in your AWS account via Cloudformation)
