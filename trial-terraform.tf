provider "aws" {
  region = "us-west-2"
}

## Instance 1 in public subnet
resource "aws_instance" "Instance1" {
  ami           = "ami-055e3d4f0bbeb5878"  
  instance_type = "t2.micro"
  availability_zone = "us-west-2a"
  tags = {
    Name = "Instance1"
  }
}