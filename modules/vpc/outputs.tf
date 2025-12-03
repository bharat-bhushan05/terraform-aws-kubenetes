output "vpc_id" {
    value = aws_vpc.cluster_vpc.id
}   

output "igw_id" {
    value = aws_internet_gateway.cluster_igw.id
}

output "subnet_id" {
  value = aws_subnet.cluster_subnet.id
}