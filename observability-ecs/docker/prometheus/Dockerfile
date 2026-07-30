FROM prom/prometheus:v3.12.0
COPY configs/prometheus/prometheus.yml /etc/prometheus/prometheus.yml
ENTRYPOINT ["/bin/prometheus"]
CMD ["--config.file=/etc/prometheus/prometheus.yml", \
     "--web.enable-remote-write-receiver", \
     "--enable-feature=exemplar-storage", \
     "--storage.tsdb.retention.time=15d", \
     "--storage.tsdb.path=/prometheus"]
