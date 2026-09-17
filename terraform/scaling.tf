resource "aws_launch_template" "web" {
  count         = local.use_managed_services ? 1 : 0
  name_prefix   = "${local.prefixe}-web-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = local.current_environment.instance_type
  key_name      = aws_key_pair.web.key_name

  vpc_security_group_ids = [aws_security_group.web.id]

  dynamic "iam_instance_profile" {
    for_each = local.use_managed_services ? [1] : []
    content {
      name = aws_iam_instance_profile.web[0].name
    }
  }

  user_data = base64encode(<<-USERDATA
    #!/bin/bash
    set -eux
    apt-get update
    apt-get install -y docker.io docker-compose-plugin awscli jq
    systemctl enable --now docker
    mkdir -p /opt/taylor-shift
    secret_json=$(aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.database.arn} --query SecretString --output text --region ${var.region})
    db_host=$(echo "$secret_json" | jq -r .host)
    db_port=$(echo "$secret_json" | jq -r .port)
    db_name=$(echo "$secret_json" | jq -r .database)
    db_user=$(echo "$secret_json" | jq -r .username)
    db_password=$(echo "$secret_json" | jq -r .password)
    cat > /opt/taylor-shift/compose.yml <<'COMPOSE'
    services:
      prestashop:
        image: prestashop/prestashop:latest
        restart: unless-stopped
        ports:
          - "80:80"
        environment:
          DB_SERVER: REPLACE_DB_HOST
          DB_PORT: "REPLACE_DB_PORT"
          DB_NAME: REPLACE_DB_NAME
          DB_USER: REPLACE_DB_USER
          DB_PASSWD: REPLACE_DB_PASSWORD
          PS_INSTALL_AUTO: "1"
          PS_DOMAIN: "${aws_lb.application[0].dns_name}"
          PS_LANGUAGE: fr
          PS_COUNTRY: fr
        volumes:
          - prestashop_data:/var/www/html
    volumes:
      prestashop_data:
    COMPOSE
    sed -i "s|REPLACE_DB_HOST|$db_host|; s|REPLACE_DB_PORT|$db_port|; s|REPLACE_DB_NAME|$db_name|; s|REPLACE_DB_USER|$db_user|; s|REPLACE_DB_PASSWORD|$db_password|" /opt/taylor-shift/compose.yml
    docker compose -f /opt/taylor-shift/compose.yml up -d
  USERDATA
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${local.prefixe}-asg", Role = "webservers" }
  }
}

resource "aws_autoscaling_group" "web" {
  count                     = local.use_managed_services ? 1 : 0
  name                      = "${local.prefixe}-web"
  min_size                  = local.current_environment.asg_min_size
  max_size                  = local.current_environment.asg_max_size
  desired_capacity          = local.current_environment.asg_desired_capacity
  vpc_zone_identifier       = [for subnet in aws_subnet.public : subnet.id]
  target_group_arns         = [aws_lb_target_group.application[0].arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.web[0].id
    version = "$Latest"
  }

  tag {
    key                 = "Environment"
    value               = var.environnement
    propagate_at_launch = true
  }
}