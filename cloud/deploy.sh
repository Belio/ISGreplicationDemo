#!/usr/bin/env bash

STACK_NAME=$1

TEMPLATE_BODY="file://cloud/couchbase.template"
REGION=`aws configure get region`

#Universal Settings
Username="Administrator" #For the Couchbase Web Console
Password="password" #For the Couchbase Web Console
Bucket="stores" #bucket name
KeyName="couchbase-${REGION}" #The ssh key that will be used to connect to the nodes
License=BYOL #Couchbase Server license use: BYOL or HourlyPricing

#Couchbase Server Settings
InstanceType="t3.medium" #Couchbase Server Instance Type
ServerInstanceCount="1"
ServerDiskSize="30"
ServerVersion="6.6.5"
Services="data\\,index\\,query" #separate each service with \\, e.g data\\,index\\,query\\,fts\\,eventing\\,analytics


#Couchbase Sync Gateway Settings
SyncGatewayVersion="2.8.3"
SyncGatewayInstanceCount="1"
SyncGatewayInstanceType="t3.medium"

aws cloudformation create-stack \
--capabilities CAPABILITY_IAM \
--template-body ${TEMPLATE_BODY} \
--stack-name ${STACK_NAME} \
--region ${REGION} \
--parameters \
ParameterKey=ServerInstanceCount,ParameterValue=${ServerInstanceCount} \
ParameterKey=ServerDiskSize,ParameterValue=${ServerDiskSize} \
ParameterKey=SyncGatewayInstanceCount,ParameterValue=${SyncGatewayInstanceCount} \
ParameterKey=InstanceType,ParameterValue=${InstanceType} \
ParameterKey=Username,ParameterValue=${Username} \
ParameterKey=Password,ParameterValue=${Password} \
ParameterKey=Bucket,ParameterValue=${Bucket} \
ParameterKey=KeyName,ParameterValue=${KeyName} \
ParameterKey=Services,ParameterValue=${Services} \
ParameterKey=ServerVersion,ParameterValue=${ServerVersion} \
ParameterKey=SyncGatewayVersion,ParameterValue=${SyncGatewayVersion} \
ParameterKey=License,ParameterValue=${License}