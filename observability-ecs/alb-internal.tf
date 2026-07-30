# Internal ALB — VPC-only entry point for the backend service's OTLP traffic.
# No WAF, no TLS, no bearer token: the security group (alb_internal, see
# security-groups.tf) is the entire trust boundary. Has its OWN target group
# (not shared with the public ALB — AWS doesn't allow one target group across
# multiple load balancers, contrary to what an earlier assumption thought).

resource "aws_lb_target_group" "alloy_internal" {
  name        = "${var.project_name}-alloy-internal"
  port        = 4318
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    path     = "/-/ready"
    port     = "12345"
    protocol = "HTTP"
    matcher  = "200"
  }
}

resource "aws_lb" "internal" {
  name               = "${var.project_name}-internal"
  internal           = true
  load_balancer_type = "application"
  subnets            = module.vpc.private_subnets
  security_groups    = [aws_security_group.alb_internal.id]
}

resource "aws_lb_listener" "internal" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 4318
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alloy_internal.arn
  }
}
