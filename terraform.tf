## Provider Block
provider "aws" {
  region = "us-west-2"
}


## VPC Creation
resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "MainVPC"
  }
}

## PublicSubnet1
resource "aws_subnet" "publicsubnet1" {
  vpc_id     = aws_vpc.main_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-west-2a"
  map_public_ip_on_launch = true
  tags = {
    Name = "PublicSubnet1"
  }
}

## PublicSubnet2
resource "aws_subnet" "publicsubnet2" {
  vpc_id     = aws_vpc.main_vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-west-2b"
  map_public_ip_on_launch = true
  tags = {
    Name = "PublicSubnet2"
  }
}


## PrivateSubnet
resource "aws_subnet" "privatesubnet" {
  vpc_id     = aws_vpc.main_vpc.id
  cidr_block = "10.0.3.0/24"
  tags = {
    Name = "PrivateSubnet"
  }
}

## Internet gateway - to allow vpc to internet

resource "aws_internet_gateway" "int_gate" {
  vpc_id = aws_vpc.main_vpc.id
  tags = {
    Name = "InternetGateway"
  }
}

## Route Table for Public Subnet
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.int_gate.id
  }

  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table_association" "public_rt_assoc1" {
  subnet_id      = aws_subnet.publicsubnet1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_rt_assoc2" {
  subnet_id      = aws_subnet.publicsubnet2.id
  route_table_id = aws_route_table.public_rt.id
}

## Instance 1 in private subnet
resource "aws_instance" "private_instance" {
  ami           = "ami-055e3d4f0bbeb5878"  
  instance_type = "t2.micro"
  availability_zone = "us-west-2a"
  subnet_id = aws_subnet.privatesubnet.id
  tags = {
    Name = "PrivateInstance"
  }
}


## Application Load Balancer
resource "aws_lb" "application_LB" {
  name               = "PublicALB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = [aws_subnet.publicsubnet1.id, aws_subnet.publicsubnet2.id]
}


## Network Load Balancer
resource "aws_lb" "network_LB" {
  name               = "PrivateNLB"
  internal           = false
  load_balancer_type = "network"
  subnets            = [aws_subnet.privatesubnet.id]
}

## Target group by application load balancer

resource "aws_lb_target_group" "alb_tg" {
  name     = "Application-LB-TG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main_vpc.id
}

## Target group by network load balancer

resource "aws_lb_target_group" "nlb_tg" {
  name     = "Network-LB-TG"
  port     = 80
  protocol = "TCP"
  vpc_id   = aws_vpc.main_vpc.id
}

## Listener for ALB
resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.application_LB.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_tg.arn
  }
}

## Listener for NLB
resource "aws_lb_listener" "nlb_listener" {
  load_balancer_arn = aws_lb.network_LB.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb_tg.arn
  }
}

## Security Group for Load Balancers
resource "aws_security_group" "lb_sg" {
  name        = "LB-SG"
  description = "Security group for Load Balancers"
  vpc_id      = aws_vpc.main_vpc.id

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

  tags = {
    Name = "LB-SG"
  }
}


## Security Group for Public Subnet
resource "aws_security_group" "public_SG" {
  name        = "Public-SG"
  description = "Security group to allow HTTP and SSH to Private Subnet"
  vpc_id      = aws_vpc.main_vpc.id 
  
  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
   tags = {
    Name = "Public-SG"
  }
}

# Security group for the Private Subnet
resource "aws_security_group" "private_SG" {
  name        = "Private-SG"
  description = "Allow traffic from public_sg only"
  vpc_id      = aws_vpc.main_vpc.id   

  ingress {
    description     = "Allow traffic from public_sg"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.public_SG.id]
  }
   tags = {
    Name = "Private-SG"
  }
}


## Creating a Auto scaling group

resource "aws_launch_template" "asg_launch_template" {
  name_prefix   = "ASG-Launch-Template"
  image_id      = "ami-055e3d4f0bbeb5878"
  instance_type = "t2.micro"
  iam_instance_profile {
    name = aws_iam_instance_profile.s3_access_instance_profile.name
  }
  security_group_names = [aws_security_group.public_SG.name]
}

resource "aws_autoscaling_group" "asg" {
  availability_zones = ["us-west-2a","us-west-2b"]
  desired_capacity   = 2
  max_size           = 3
  min_size           = 1

  launch_template {
    id      = aws_launch_template.asg_launch_template.id
    version = "$Latest"
  }
  target_group_arns = [aws_lb_target_group.alb_tg.arn]
}


## Creating a IAM instance profile - used to attach an iam role to an ec2 instance

resource "aws_iam_instance_profile" "s3_access_instance_profile"{
  name = "s3-access-instance-profile"
  role = aws_iam_role.s3_access_role.name
}


## S3 Bucket
resource "aws_s3_bucket" "s3_bucket" {
  bucket = "my-bucket"

  tags = {
    Name = "My bucket"
  }
}

## Enabling Versioning
resource "aws_s3_bucket_versioning" "s3_versioning" {
  bucket = aws_s3_bucket.s3_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

## Restricting public access
resource "aws_s3_bucket_public_access_block" "s3_access" {
  bucket = aws_s3_bucket.s3_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


## Creating IAM Role
resource "aws_iam_role" "s3_access_role" {
  name = "s3-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}


## Creating a IAM Policy
resource "aws_iam_policy" "s3_access_policy" {
  name   = "s3-access-policy"
  description = "Full permission to access S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "s3:*" ,
        Resource = [
		  "${aws_s3_bucket.s3_bucket.arn}",
          "${aws_s3_bucket.s3_bucket.arn}/*" ,
        ]
      }
    ]
  })
}


## Attaching an IAM Policy to IAM role
resource "aws_iam_role_policy_attachment" "s3_role_policy_attachment" {
  role       = aws_iam_role.s3_access_role.name
  policy_arn = aws_iam_policy.s3_access_policy.arn
}