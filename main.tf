provider "aws" {
  region = "us-east-2"  # Update with your desired region
}

resource "aws_vpc" "terraform6" {
  cidr_block = var.cidr_block
}

resource "aws_subnet" "public_subnets" {
  count                  = 3
  vpc_id                 = aws_vpc.terraform6.id
  cidr_block             = "10.0.${count.index}.0/24"
  availability_zone      = element(var.availability_zones, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count                  = 3
  vpc_id                 = aws_vpc.terraform6.id
  cidr_block             = "10.0.${count.index + 10}.0/24"  
  availability_zone      = element(var.availability_zones, count.index)

  tags = {
    Name = "private-subnet-${count.index + 1}"
  }
}

resource "aws_security_group" "public_sg" {
  vpc_id = aws_vpc.terraform6.id

  # Define inbound and outbound rules as needed
}

resource "aws_security_group" "private_sg" {
  vpc_id = aws_vpc.terraform6.id

  # Define inbound and outbound rules as needed
}


resource "aws_launch_configuration" "ec2_launch_config" {
  name          = "ec2-launch-config"
  image_id      = "ami-0ddda618e961f2270"  # Update with your desired AMI
  instance_type = "t2.micro"      # Update with your desired instance type
  key_name = "tuncay"
  security_groups = [aws_security_group.public_sg.id]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "ec2_asg" {
  launch_configuration = aws_launch_configuration.ec2_launch_config.id
  min_size             = 3
  max_size             = 5
  desired_capacity     = 3
 
  vpc_zone_identifier  = aws_subnet.public_subnets[*].id  # Corrected

  tag {
    key                 = "Name"
    value               = "ec2-instance"
    propagate_at_launch = true
  }
}

# Define RDS database instances
resource "aws_db_instance" "db_instance" {
  count                 = 1
  allocated_storage     = 10
  engine                = "mysql"
  engine_version        = "5.7"
  instance_class        = "db.t3.micro"
  username              = "admin"
  password              = "password"
  multi_az              = true
  publicly_accessible   = false

  tags = {
    Name = "db-instance-${count.index}"
  }
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "my-db-subnet-group"
  subnet_ids = aws_subnet.private_subnets[*].id  # Corrected
}

variable "cidr_block" {
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-2a", "us-east-2b", "us-east-2c"]
}

resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.terraform6.id
}

resource "aws_lb" "app_lb" {
  name               = "my-app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.public_sg.id]
  subnets            = aws_subnet.public_subnets[*].id  # Use public subnets for the ALB

  tags = {
    Name = "my-app-lb"
  }
}

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "OK"
      status_code  = 200
    }
}
}

resource "aws_lb_target_group" "app_target_group" {
  name     = "my-app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.terraform6.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
  }
}

resource "aws_lb_listener_rule" "app_listener_rule" {
  listener_arn = aws_lb_listener.http_listener.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_target_group.arn
  }

  condition {
    host_header {
      values = ["example.com"]  # Replace with your domain name
    }
  }
}
