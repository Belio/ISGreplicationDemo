couchbase_server_url=`cat /etc/sync_gateway/template.json | grep '"server":' | grep -o '"http://.*"' | sed 's/"//g'`

while ! { curl -X GET -u Administrator:password $couchbase_server_url/pools/default/buckets -H "accept: application/json" -s | grep -q '"status":"healthy"'; }; do
  echo "Waiting for the Couchbase server on $couchbase_server_url to become available"
  sleep 15
done

query_url=$(sed 's/8091/8093/g' <<< $couchbase_server_url)

echo "endpoint is " $query_url/query/service

until $(curl -u Administrator:password --output /dev/null --fail --silent $query_url/query/service -d 'statement=SELECT RAW 1'); do
      printf 'waiting for query service to be up...\n'
      sleep 15
done

sleep 30

remote="http://$REMOTE_ADDRESS:4984/stores"
echo "remote address is $remote" 

#configure replication with remote sync_gateway
sed -e 's/admin_interface/'"$ADMIN_INTERFACE"'/g' -e 's/main_interface/'"$INTERFACE"'/g' -e 's/metrics_interface/'"$METRICS_INTERFACE"'/g' -e 's/remote_address/'"http:\/\/$REMOTE_ADDRESS:4984\/stores"'/g' /etc/sync_gateway/template.json > /home/sync_gateway/config.json

/entrypoint.sh /home/sync_gateway/config.json