FROM grafana/loki:3.7.2
COPY docker/loki/loki.yml /etc/loki/loki.yml
ENTRYPOINT ["/usr/bin/loki"]
CMD ["-config.file=/etc/loki/loki.yml"]
