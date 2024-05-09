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

  // Define inbound rules for public subnets
  // Allow inbound traffic for ports 80 (HTTP), 443 (HTTPS), and 22 (SSH)
  // from any source (0.0.0.0/0) for public subnets
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // Define outbound rules for public subnets
  // Allow all outbound traffic from public subnets
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" // All protocols
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "private_sg" {
  vpc_id = aws_vpc.terraform6.id

  // Define outbound rules for private subnets
  // Allow all outbound traffic from private subnets
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" // All protocols
    cidr_blocks = ["0.0.0.0/0"]
  }
}

// Add inbound rule for RDS access
// Allow inbound traffic on port 3306 (MySQL) from specific sources
resource "aws_security_group_rule" "rds_access" {
  type              = "ingress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  security_group_id = aws_security_group.private_sg.id

  // Adjust the source_cidr_blocks parameter to allow access only from specific sources
  cidr_blocks = ["0.0.0.0/0"] // Example: Allow access from any IP address
}



resource "aws_launch_configuration" "ec2_launch_config" {
  name          = "ec2-launch-config"
  image_id      = "ami-0ddda618e961f2270"  # Update with your desired AMI
  instance_type = "t2.micro"      # Update with your desired instance type
  key_name = "tuncay"
  security_groups = [aws_security_group.public_sg.id]
  user_data     = <<-EOF
                  #!/bin/bash
                  yum update -y
                  yum install -y httpd php php-mysqlnd
                  systemctl start httpd
                  systemctl enable httpd
                  wget -c https://wordpress.org/latest.tar.gz
                  tar -xvzf latest.tar.gz -C /var/www/html
                  cp -r /var/www/html/wordpress/* /var/www/html/
                  chown -R apache:apache /var/www/html/
                  EOF

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
  skip_final_snapshot   = true
  final_snapshot_identifier = "terraform-20240509003343928000000001-snapshot"

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

# Create a public route table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.terraform6.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.example.id  # Use the internet gateway created earlier
  }

  tags = {
    Name = "public-route-table"
  }
}

# Associate public subnets with the public route table
resource "aws_route_table_association" "public_subnet_association" {
  count          = 3
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Create a private route table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.terraform6.id

  tags = {
    Name = "private-route-table"
  }
}

# Create NAT gateway(s)
resource "aws_nat_gateway" "nat_gateway" {
  count        = 3  # One NAT gateway per availability zone
  subnet_id    = aws_subnet.public_subnets[count.index].id
  allocation_id = aws_eip.nat_eip[count.index].id

  tags = {
    Name = "nat-gateway-${count.index}"
  }
}

# Create Elastic IPs for the NAT gateways
resource "aws_eip" "nat_eip" {
  count = 3

  vpc      = true
}

# Create a route in the private route table to route traffic through the NAT gateway
resource "aws_route" "private_route" {
  count          = 3
  route_table_id = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.nat_gateway[count.index].id
}

resource "aws_route53_zone" "example_zone" {
  name = "example.com"
}

resource "aws_route53_record" "example_lb_record" {
  zone_id = aws_route53_zone.example_zone.zone_id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_lb.app_lb.dns_name
    zone_id                = aws_lb.app_lb.zone_id
    evaluate_target_health = true
  }
}
