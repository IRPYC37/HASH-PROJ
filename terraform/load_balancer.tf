resource "aws_lb" "application" {
  count              = local.use_managed_services ? 1 : 0
  name               = "${local.prefixe}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for subnet in aws_subnet.public : subnet.id]
}

resource "aws_lb_target_group" "application" {
  count    = local.use_managed_services ? 1 : 0
  name     = "${local.prefixe}-web"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  count             = local.use_managed_services ? 1 : 0
  load_balancer_arn = aws_lb.application[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.application[0].arn
  }
}

resource "aws_lb_target_group_attachment" "web" {
  count            = local.use_managed_services ? length(aws_instance.web) : 0
  target_group_arn = aws_lb_target_group.application[0].arn
  target_id        = aws_instance.web[format("web%d", count.index + 1)].id
  port             = 80
}