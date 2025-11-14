terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "6.20.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}


resource "aws_vpc" "kotval_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "Terraform-VPC"
  }
}


resource "aws_subnet" "kotval_subnet" {
  
  vpc_id     = aws_vpc.kotval_vpc.id
  
  cidr_block = "10.0.1.0/24"
  tags = {
    Name = "Terraform-Subnet"
  }
}


data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }
}


resource "aws_security_group" "web_sg" {
  name        = "asg-web-sg"
  description = "Allow HTTP traffic to web servers"
  vpc_id      = aws_vpc.kotval_vpc.id


  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_launch_template" "kotval_web_server_lt" {
  name_prefix   = "web-server-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web_sg.id]
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Hello Kötvál HW 4! This is my page!</h1>" > /var/www/html/index.html
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "ASG-Web-Server"
    }
  }
}


resource "aws_autoscaling_group" "web_asg" {

  desired_capacity    = 3
  max_size            = 4
  min_size            = 1
  

  vpc_zone_identifier = [aws_subnet.kotval_subnet.id]


  launch_template {
    id      = aws_launch_template.kotval_web_server_lt.id
    version = "$Latest"
  }
}


resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.kotval_vpc.id

  tags = {
    Name = "main-gateway"
  }
}


resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.kotval_vpc.id


  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "public-route-table"
  }
}


resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.kotval_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

data "aws_instances" "asg_instances" {
  instance_tags = {
    Name = "ASG-Web-Server"
  }
  
  instance_state_names = ["running"]

  depends_on = [aws_autoscaling_group.web_asg]
}


output "asg_public_ips" {
  value = data.aws_instances.asg_instances.public_ips
}