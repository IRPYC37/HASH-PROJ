resource "aws_sns_topic" "alertes" {
  count = local.use_managed_services ? 1 : 0
  name  = "${local.prefixe}-alertes"
}

resource "aws_sns_topic_subscription" "alertes_email" {
  count     = local.use_managed_services && var.alert_email != null ? 1 : 0
  topic_arn = aws_sns_topic.alertes[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  count               = local.use_managed_services ? 1 : 0
  alarm_name          = "${local.prefixe}-alb-unhealthy-hosts"
  alarm_description   = "Une instance applicative ne répond plus au health check ALB."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  alarm_actions       = [aws_sns_topic.alertes[0].arn]
  ok_actions          = [aws_sns_topic.alertes[0].arn]
  dimensions = {
    LoadBalancer = aws_lb.application[0].arn_suffix
    TargetGroup  = aws_lb_target_group.application[0].arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  count               = local.use_managed_services ? 1 : 0
  alarm_name          = "${local.prefixe}-rds-cpu"
  alarm_description   = "La base RDS consomme durablement trop de CPU."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanOrEqualToThreshold"
  alarm_actions       = [aws_sns_topic.alertes[0].arn]
  ok_actions          = [aws_sns_topic.alertes[0].arn]
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main[0].id
  }
}
