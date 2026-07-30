auth_enabled: false

server:
  http_listen_port: 3100

common:
  path_prefix: /loki
  storage:
    s3:
      endpoint: s3.${region}.amazonaws.com
      region: ${region}
      bucketnames: ${bucket_name}
      insecure: false
      # No access_key / secret_key — uses the Loki ECS task role
      s3forcepathstyle: false
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: "2024-01-01"
      store: tsdb
      object_store: s3
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  retention_period: ${retention_hours}h
  max_line_size: 262144
  max_label_names_per_series: 15

compactor:
  working_directory: /loki/compactor
  retention_enabled: true
  retention_delete_delay: 2h
  delete_request_store: s3

analytics:
  reporting_enabled: false
