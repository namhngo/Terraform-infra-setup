# S3 gateway endpoint — free. Routes all S3 traffic from the private subnets
# over AWS's internal network instead of out through the NAT gateway. Two
# things benefit: Loki/Tempo reading and writing their buckets, and ECR image
# layer pulls (ECR stores layers in S3). This also trims NAT data-processing
# charges, since that traffic no longer transits the NAT.
#
# NOTE: this is a *gateway* endpoint (S3 and DynamoDB are the only two AWS
# offers as gateway type). It attaches to route tables, costs nothing, and
# needs no security group. Reaching ECR's API itself, STS, EC2, etc. would
# require *interface* endpoints (~$7/mo each per AZ) — only necessary if the
# NAT gateway were removed. See the README for that trade-off.

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids

  tags = { Name = "${var.project_name}-s3" }
}
