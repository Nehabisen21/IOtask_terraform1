##### VPC 1###################

resource "aws_vpc" "my_vpc1" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

# SUBNETS FOR VPC1

resource "aws_subnet" "vpc1sub_public" {
  vpc_id                  = aws_vpc.my_vpc1.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
}

resource "aws_subnet" "vpc1sub_private" {
  vpc_id            = aws_vpc.my_vpc1.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
}

# INTERNET GATEWAY

resource "aws_internet_gateway" "gateway1" {
  vpc_id = aws_vpc.my_vpc1.id
}

# PUBLIC ROUTE TABLE

resource "aws_route_table" "my_rt1" {
  vpc_id = aws_vpc.my_vpc1.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gateway1.id
  }
}

resource "aws_route_table_association" "pub_rta1" {
  subnet_id      = aws_subnet.vpc1sub_public.id
  route_table_id = aws_route_table.my_rt1.id
}

# NAT GATEWAY + EIP

resource "aws_eip" "nat_eip1" {
  depends_on = [aws_internet_gateway.gateway1]
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip1.id
  subnet_id     = aws_subnet.vpc1sub_public.id
}

# PRIVATE ROUTE TABLE

resource "aws_route_table" "my_rt2private" {
  vpc_id = aws_vpc.my_vpc1.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
}

resource "aws_route_table_association" "pri_rta2" {
  subnet_id      = aws_subnet.vpc1sub_private.id
  route_table_id = aws_route_table.my_rt2private.id
}

# SECURITY GROUP FOR BASTION

resource "aws_security_group" "bastion_sg" {
  vpc_id      = aws_vpc.my_vpc1.id
  description = "Allow SSH to bastion"

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]   # change to your IP in production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# NACL FOR PRIVATE SUBNET (no subnet_ids here, use association resource)

resource "aws_network_acl" "my_nacl_privatesub" {
  vpc_id = aws_vpc.my_vpc1.id

  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "10.0.0.0/16"
    from_port  = 0
    to_port    = 65535
  }

  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
}

resource "aws_network_acl_association" "private_nacl_assoc" {
  network_acl_id = aws_network_acl.my_nacl_privatesub.id
  subnet_id      = aws_subnet.vpc1sub_private.id
}

# INSTANCES IN VPC1

resource "aws_instance" "bastion" {
  ami                    = "ami-0ecb62995f68bb549"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.vpc1sub_public.id
  key_name               = "aws-key"
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  tags = { Name = "Bastion-Host" }
}

resource "aws_security_group" "private_ec2_sg" {
  vpc_id = aws_vpc.my_vpc1.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]  # allow SSH from public subnet (bastion)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "private_instance" {
  ami                    = "ami-0ecb62995f68bb549"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.vpc1sub_private.id
  key_name               = "aws-key"
  vpc_security_group_ids = [aws_security_group.private_ec2_sg.id]

  tags = { Name = "Private-EC2" }
}

############################################
# VPC 2
############################################

resource "aws_vpc" "my_vpc2" {
  cidr_block = "192.168.0.0/16"
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.my_vpc2.id
  cidr_block        = "192.168.1.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "private_subnet2" {
  vpc_id            = aws_vpc.my_vpc2.id
  cidr_block        = "192.168.2.0/24"
  availability_zone = "us-east-1b"
}

############################################
# SECURITY GROUP FOR RDS
############################################

resource "aws_security_group" "rds_sg" {
  name        = "rds_sg"
  vpc_id      = aws_vpc.my_vpc2.id
  description = "Allow RDS MySQL access"

  ingress {
    protocol    = "tcp"
    from_port   = 3306
    to_port     = 3306
    cidr_blocks = ["10.0.0.0/16"]  # Allow VPC1
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

### Route Table for VPC2 ###

resource "aws_route_table" "vpc2_route_table" {
  vpc_id = aws_vpc.my_vpc2.id

  tags = {
    Name = "vpc2-route-table"
  }
}

## Route Table Association for VPC2 ###

resource "aws_route_table_association" "vpc2_rta1" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.vpc2_route_table.id
}

resource "aws_route_table_association" "vpc2_rta2" {
  subnet_id      = aws_subnet.private_subnet2.id
  route_table_id = aws_route_table.vpc2_route_table.id
}

############################################
# DB SUBNET GROUP + RDS
############################################

resource "aws_db_subnet_group" "my_db_subgrp" {
  name       = "rds-subgrp"
  subnet_ids = [aws_subnet.private_subnet.id, aws_subnet.private_subnet2.id]
}

resource "aws_db_instance" "RDS" {
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = "mydatabase"
  username               = "useradmin"
  password               = "Pass1234"
  db_subnet_group_name   = aws_db_subnet_group.my_db_subgrp.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
}

############################################
# VPC2 Private EC2
############################################

resource "aws_security_group" "ec2_sg_vpc2" {
  vpc_id = aws_vpc.my_vpc2.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]  # allow SSH from VPC1
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "vpc2_private_ec2" {
  ami                    = "ami-0ecb62995f68bb549"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_subnet2.id
  key_name               = "aws-key"
  vpc_security_group_ids = [aws_security_group.ec2_sg_vpc2.id]
}

############################################
# VPC PEERING
############################################

resource "aws_vpc_peering_connection" "peering" {
  vpc_id      = aws_vpc.my_vpc1.id
  peer_vpc_id = aws_vpc.my_vpc2.id
  peer_region = "us-east-1"
  auto_accept = false

  tags = { Side = "Requester" }
}

resource "aws_vpc_peering_connection_accepter" "peeringaccept" {
  vpc_peering_connection_id = aws_vpc_peering_connection.peering.id
  auto_accept               = true

  tags = { Side = "Accepter" }
}

############################################
# ROUTES FOR PEERING (both sides)
############################################

resource "aws_route" "vpc1_to_vpc2" {
  route_table_id            = aws_route_table.my_rt2private.id
  destination_cidr_block    = "192.168.0.0/16"
  vpc_peering_connection_id = aws_vpc_peering_connection.peering.id
}

resource "aws_route" "vpc2_to_vpc1" {
  route_table_id            = aws_route_table.vpc2_route_table.id
  destination_cidr_block    = "10.0.0.0/16"
  vpc_peering_connection_id = aws_vpc_peering_connection.peering.id
}

############################################
# OUTPUTS
############################################

output "vpc1_id" {
  value = aws_vpc.my_vpc1.id
}

output "vpc2_id" {
  value = aws_vpc.my_vpc2.id
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "private_instance_private_ip" {
  value = aws_instance.private_instance.private_ip
}

output "vpc_peering_id" {
  value = aws_vpc_peering_connection.peering.id
}

output "rds_endpoint" {
  value = aws_db_instance.RDS.endpoint
}
