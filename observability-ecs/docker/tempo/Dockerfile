FROM grafana/tempo:2.10.7
COPY docker/tempo/tempo.yml /etc/tempo/tempo.yml
ENTRYPOINT ["/tempo"]
CMD ["-config.file=/etc/tempo/tempo.yml"]
