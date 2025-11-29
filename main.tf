##########################
# VPC 1
##########################
resource "aws_vpc" "my_vpc1" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "vpc1" }
}

# SUBNETS FOR VPC1 (public used for endpoint ENI; private used for bastion & private instances)
resource "aws_subnet" "vpc1sub_public" {
  vpc_id                  = aws_vpc.my_vpc1.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags = { Name = "vpc1-public-subnet" }
}

resource "aws_subnet" "vpc1sub_private" {
  vpc_id            = aws_vpc.my_vpc1.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "vpc1-private-subnet" }
}

# INTERNET GATEWAY
resource "aws_internet_gateway" "gateway1" {
  vpc_id = aws_vpc.my_vpc1.id
  tags = { Name = "vpc1-igw" }
}

# PUBLIC ROUTE TABLE
resource "aws_route_table" "my_rt1" {
  vpc_id = aws_vpc.my_vpc1.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gateway1.id
  }

  tags = { Name = "vpc1-public-rt" }
}

resource "aws_route_table_association" "pub_rta1" {
  subnet_id      = aws_subnet.vpc1sub_public.id
  route_table_id = aws_route_table.my_rt1.id
}

# NAT GATEWAY + EIP
resource "aws_eip" "nat_eip1" {
  depends_on = [aws_internet_gateway.gateway1]
  tags = { Name = "vpc1-nat-eip" }
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip1.id
  subnet_id     = aws_subnet.vpc1sub_public.id
  tags = { Name = "vpc1-natgw" }
}

# PRIVATE ROUTE TABLE
resource "aws_route_table" "my_rt2private" {
  vpc_id = aws_vpc.my_vpc1.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }

  tags = { Name = "vpc1-private-rt" }
}

resource "aws_route_table_association" "pri_rta2" {
  subnet_id      = aws_subnet.vpc1sub_private.id
  route_table_id = aws_route_table.my_rt2private.id
}

# SECURITY GROUP FOR BASTION
resource "aws_security_group" "bastion_sg" {
  name        = "bastion-sg"
  description = "Allow SSH only from Instance Connect Endpoint ENI subnet"
  vpc_id      = aws_vpc.my_vpc1.id

  ingress {
    description = "SSH from EICE ENI subnet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.vpc1sub_public.cidr_block]
  }
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"] #temporary for testing  
  }
 ingress {
  protocol  = "icmp"
  from_port = -1
  to_port   = -1
  cidr_blocks = ["192.168.2.29/32"]#allow ping from VPC2 private EC2 Ip
}


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "bastion-sg" }
}

# SECURITY GROUP FOR PRIVATE EC2
resource "aws_security_group" "private_ec2_sg" {
  name   = "private-ec2-sg"
  vpc_id = aws_vpc.my_vpc1.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.vpc1sub_private.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "private-ec2-sg" }
}

# NACL FOR PRIVATE SUBNET
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

  tags = { Name = "vpc1-private-nacl" }
}

resource "aws_network_acl_association" "private_nacl_assoc" {
  network_acl_id = aws_network_acl.my_nacl_privatesub.id
  subnet_id      = aws_subnet.vpc1sub_private.id
}

# IAM policy for EICE
data "aws_iam_policy_document" "eic_policy_doc" {
  statement {
    actions   = ["ec2-instance-connect:SendSSHPublicKey"]
    resources = ["*"]
    }
}

resource "aws_iam_policy" "eic_policy" {
  name   = "EICE-SendSSHPublicKey-Policy"
  policy = data.aws_iam_policy_document.eic_policy_doc.json
}

# EC2 Instance Connect Endpoint SG
resource "aws_security_group" "eice_sg" {
  name        = "eice-sg"
  description = "SG for EC2 Instance Connect Endpoint"
  vpc_id      = aws_vpc.my_vpc1.id

  ingress {
    description = "SSH from admin IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["54.198.78.81/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "eice-sg" }
}

# EC2 Instance Connect Endpoint
resource "aws_ec2_instance_connect_endpoint" "eice" {
  subnet_id          = aws_subnet.vpc1sub_public.id
  security_group_ids = [aws_security_group.eice_sg.id]


  tags = { Name = "EICE-Endpoint" }
}

##############################
# BASTION SERVER (PUBLIC)
##############################
resource "aws_instance" "bastion" {
  ami                         = "ami-0ecb62995f68bb549"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.vpc1sub_public.id     # ← moved to PUBLIC subnet
  key_name                    = "aws-key"
  associate_public_ip_address = true                              # ← public IP ENABLED
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]

  tags = { Name = "Public-Bastion" }
}

# PRIVATE EC2
resource "aws_instance" "private_instance" {
  ami                    = "ami-0ecb62995f68bb549"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.vpc1sub_private.id
  key_name               = "aws-key"
  vpc_security_group_ids = [aws_security_group.private_ec2_sg.id]

  tags = { Name = "Private-EC2" }
}

##########################
# VPC 2
##########################
resource "aws_vpc" "my_vpc2" {
  cidr_block = "192.168.0.0/16"
  tags = { Name = "vpc2" }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.my_vpc2.id
  cidr_block        = "192.168.1.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "vpc2-private-subnet-a" }
}

resource "aws_subnet" "private_subnet2" {
  vpc_id            = aws_vpc.my_vpc2.id
  cidr_block        = "192.168.2.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "vpc2-private-subnet-b" }
}

# SECURITY GROUP FOR RDS
resource "aws_security_group" "rds_sg" {
  name        = "rds_sg"
  vpc_id      = aws_vpc.my_vpc2.id
  description = "Allow RDS MySQL access"

  ingress {
    protocol    = "tcp"
    from_port   = 3306
    to_port     = 3306
    cidr_blocks = [aws_vpc.my_vpc1.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "rds-sg" }
}

### Route Table for VPC2 ###
resource "aws_route_table" "vpc2_route_table" {
  vpc_id = aws_vpc.my_vpc2.id
  tags = { Name = "vpc2-route-table" }
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

##########################
# DB SUBNET GROUP + RDS
##########################
resource "aws_db_subnet_group" "my_db_subgrp2" {
  name       = "rds-subgrp2"
  subnet_ids = [aws_subnet.private_subnet.id, aws_subnet.private_subnet2.id]
  tags = { Name = "rds-subnet-group2" }
}

resource "aws_db_instance" "RDS" {
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = "mydb"
  username               = "useradmin"
  password               = "Pass1234"
  db_subnet_group_name   = aws_db_subnet_group.my_db_subgrp2.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  tags = { Name = "rds-instance" }
}

##########################
# VPC2 Private EC2
##########################
resource "aws_security_group" "ec2_sg_vpc2" {
  name   = "vpc2-ec2-sg"
  vpc_id = aws_vpc.my_vpc2.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.my_vpc1.cidr_block]
    
  }
  ingress {
  protocol  = "icmp"
  from_port = -1
  to_port   = -1
  cidr_blocks = ["10.0.1.9/32"]#allow ping from bastion public IP for testing
}
  ingress  {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"] #temporary for testing


  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "vpc2-ec2-sg" }
}



  resource "aws_instance" "vpc2_private_ec2" {
  ami                    = "ami-0ecb62995f68bb549"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_subnet2.id
  key_name               = "aws-key"
  vpc_security_group_ids = [aws_security_group.ec2_sg_vpc2.id]
  tags = { Name = "vpc2-private-ec2" }
    
}


##########################
# VPC PEERING
##########################
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

# ROUTES FOR PEERING
resource "aws_route" "vpc1_to_vpc2" {
  route_table_id            = aws_route_table.my_rt1.id
  destination_cidr_block    = aws_vpc.my_vpc2.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.peering.id
}

resource "aws_route" "vpc2_to_vpc1" {
  route_table_id            = aws_route_table.vpc2_route_table.id
  destination_cidr_block    = aws_vpc.my_vpc1.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.peering.id
}

##########################
# OUTPUTS
##########################
output "vpc1_id" {
  value = aws_vpc.my_vpc1.id
}

output "vpc2_id" {
  value = aws_vpc.my_vpc2.id
}

output "bastion_private_ip" {
  value = aws_instance.bastion.private_ip
}

output "bastion_id" {
  value = aws_instance.bastion.id
}

output "vpc_peering_id" {
  value = aws_vpc_peering_connection.peering.id
}

output "rds_endpoint" {
  value = aws_db_instance.RDS.endpoint
}

output "eice_id" {
  value = aws_ec2_instance_connect_endpoint.eice.id
}
