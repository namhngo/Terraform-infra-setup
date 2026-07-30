# Internal ALB — VPC-only entry point for the backend service's OTLP traffic.
# No WAF, no TLS, no bearer token: the security group (alb_internal, see
# security-groups.tf) is the entire trust boundary. Reuses the SAME Alloy
# target group the public ALB uses (alb-public.tf) — AWS explicitly supports
# one target group registered with multiple load balancers, and Alloy has no
# reason to care which listener a request arrived through.

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
    target_group_arn = aws_lb_target_group.alloy.arn
  }
}
