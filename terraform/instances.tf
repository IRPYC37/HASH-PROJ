data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "web" {
  key_name   = "${local.prefixe}-web"
  public_key = file("${path.module}/${var.ssh_public_key_path}")
}

resource "aws_instance" "web" {
  for_each = { for index in range(local.current_environment.instance_count) : "web${index + 1}" => index }

  ami                         = var.deployment_mode == "floci" ? "ami-debian12" : data.aws_ami.ubuntu.id
  instance_type               = local.current_environment.instance_type
  subnet_id                   = aws_subnet.public[each.value % length(aws_subnet.public)].id
  vpc_security_group_ids      = [aws_security_group.web.id]
  key_name                    = aws_key_pair.web.key_name
  iam_instance_profile        = local.use_managed_services ? aws_iam_instance_profile.web[0].name : null
  associate_public_ip_address = local.use_managed_services

  tags = { Name = "${local.prefixe}-${each.key}", Role = "webservers" }
}
