server:
  http_listen_port: 3200
  grpc_listen_port: 9095

distributor:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317

ingester:
  max_block_duration: 5m

compactor:
  compaction:
    block_retention: ${retention_hours}h

metrics_generator:
  processor:
    local_blocks:
      filter_server_spans: false
  registry:
    external_labels:
      source: tempo
  storage:
    path: /var/tempo/generator/wal
    remote_write:
      - url: http://prometheus:9090/api/v1/write
        send_exemplars: true
  traces_storage:
    path: /var/tempo/generator/traces

storage:
  trace:
    backend: s3
    wal:
      path: /var/tempo/wal
    s3:
      bucket: ${bucket_name}
      endpoint: s3.${region}.amazonaws.com
      region: ${region}
      # No credentials — uses the Tempo ECS task role

overrides:
  defaults:
    metrics_generator:
      processors: [local-blocks, service-graphs, span-metrics]

usage_report:
  reporting_enabled: false
