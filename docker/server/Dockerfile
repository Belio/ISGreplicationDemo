FROM couchbase:7.0.3
RUN chmod +x /entrypoint.sh
COPY ./docker/server/startup.sh /opt/couchbase
RUN chmod +x /opt/couchbase/startup.sh

CMD ["/opt/couchbase/startup.sh"]