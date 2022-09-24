provider "aws" {
  region = "us-east-2"

  default_tags {
    tags = {
      name = "aws-asg" #manage aws auto scaling groups
    }
  }
}

#getting available zones list which states are 'available'

data "aws_availability_zones" "available" {
  state = "available"
}

#official module from aws, configuring vpc

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"

  name = "main-vpc"
  cidr = "10.0.0.0/16"

  azs                  = data.aws_availability_zones.available.names
  public_subnets       = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"]
  enable_dns_hostnames = true
  enable_dns_support   = true
}

#getting required ami
data "aws_ami" "amazon-linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-hvm-*-x86_64-ebs"]
  }
}


resource "aws_launch_configuration" "web-server" {
  name_prefix     = "learn-terraform-aws-asg-"
  image_id        = data.aws_ami.amazon-linux.id
  instance_type   = "t2.micro"
  user_data       = file("user-data.sh")  #working on it
  security_groups = [aws_security_group.web-server-sg-.id] #security group open port 8080

  lifecycle {
    create_before_destroy = true #avoid any system interruptions
  }
}

resource "aws_autoscaling_group" "web-server-asg" {
  name                 = "tomcat-web-server-asg"
  min_size             = 1
  max_size             = 3
  desired_capacity     = 1
  launch_configuration = aws_launch_configuration.web-server.name
  vpc_zone_identifier  = module.vpc.public_subnets

  tag {
    key                 = "Name"
    value               = "Tomcat Web Servers"
    propagate_at_launch = true
  }
}

resource "aws_lb" "web-server-lb" {
  name               = "web-server-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb-sg.id]
  subnets            = module.vpc.public_subnets
}

resource "aws_lb_listener" "web-server-lb-lsn" {
  load_balancer_arn = aws_lb.web-server-lb.arn
  port              = "8080"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web-server-tg.arn
  }
}

resource "aws_lb_target_group" "web-server-lb-tg" {
  name     = "tomcat-webs-server"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
}


resource "aws_autoscaling_attachment" "web-server-asg-attch" {
  autoscaling_group_name = aws_autoscaling_group.web-server-asg.id
  alb_target_group_arn   = aws_lb_target_group.web-server-lb-tg.arn
}

resource "aws_security_group" "web-server-sg" {
  name = "learn-asg-terramino-instance"
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.lb-sg.id]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.lb-sg.id]
  }

  vpc_id = module.vpc.vpc_id
}

resource "aws_security_group" "lb-sg" {
  name = "sg load balancer"
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = module.vpc.vpc_id
}
