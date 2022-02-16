#!/bin/bash
set -m
set -e

/entrypoint.sh couchbase-server &

sleep 15

# Setup initial cluster/ Initialize Node
couchbase-cli cluster-init -c 127.0.0.1 --cluster-name $CLUSTER_NAME --cluster-username $COUCHBASE_ADMINISTRATOR_USERNAME \
--cluster-password $COUCHBASE_ADMINISTRATOR_PASSWORD --services data,index,query,fts --cluster-ramsize 512 --cluster-index-ramsize 512 \
--cluster-fts-ramsize 256 --index-storage-setting default \


sleep 15

# Setup Bucket
couchbase-cli bucket-create -c 127.0.0.1:8091 --username $COUCHBASE_ADMINISTRATOR_USERNAME \
--password $COUCHBASE_ADMINISTRATOR_PASSWORD  --bucket $COUCHBASE_BUCKET --bucket-type couchbase \
--bucket-ramsize 256

sleep 15

# Setup RBAC user using CLI
couchbase-cli user-manage -c 127.0.0.1:8091 --username $COUCHBASE_ADMINISTRATOR_USERNAME --password $COUCHBASE_ADMINISTRATOR_PASSWORD \
--set --rbac-username $COUCHBASE_RBAC_USERNAME --rbac-password $COUCHBASE_RBAC_PASSWORD --rbac-name $COUCHBASE_RBAC_NAME \
    --roles bucket_full_access[*],bucket_admin[*] --auth-domain local

sleep 15

echo "creating primary index on store_local"
curl \
  --user "Administrator:password" \
  --silent \
  --data-urlencode "statement=CREATE PRIMARY INDEX idx_stores_primary ON store_local" \
  http://127.0.0.1:8093/query/service > /dev/null


# Attach to couchbase entrypoint
echo "Attaching to couchbase-server entrypoint"
fg 1