resource "aws_vpc" "cluster_vpc"{
    cidr_block = var.vpc_cidr 
    
    tags = {
    Name = "cluster"
  }
}

resource "aws_internet_gateway" "cluster_igw" {
    vpc_id = aws_vpc.cluster_vpc.id
    
    tags = {
    Name = "cluster_igw"
  } 
}

resource "aws_subnet" "cluster_subnet" {
  vpc_id     = aws_vpc.cluster_vpc.id
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone = "us-east-1a"

  tags = {
    Name = "cluster-subnet"
  }
}

resource "aws_route_table" "cluster_rt" {
  vpc_id = aws_vpc.cluster_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cluster_igw.id
  }

  tags = {
    Name = "cluster-rt"
  }
}

resource "aws_route_table_association" "cluster_rta" {
  subnet_id      = aws_subnet.cluster_subnet.id
  route_table_id = aws_route_table.cluster_rt.id
}
