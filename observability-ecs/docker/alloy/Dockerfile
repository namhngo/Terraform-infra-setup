FROM grafana/alloy:v1.17.0
COPY configs/alloy/config.alloy /etc/alloy/config.alloy
ENTRYPOINT ["/bin/alloy"]
CMD ["run", "--server.http.listen-addr=0.0.0.0:12345", "/etc/alloy/config.alloy"]
