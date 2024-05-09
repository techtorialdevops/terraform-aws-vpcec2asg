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
