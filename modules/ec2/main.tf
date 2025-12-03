data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "k8s_master" {
  count         = 1
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"
  subnet_id     = var.subnet_id
  vpc_security_group_ids = [var.master_sg_id]
  key_name      = var.key_name

  user_data = file("${path.module}/k8s-master.sh")

  tags = {
    Name = "k8s-master"
  }
}

# Workers fetch the join command directly from master via HTTP on port 8080
# No Terraform provisioner needed!

resource "aws_instance" "k8s_worker" {
  count         = 2
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"
  subnet_id     = var.subnet_id
  vpc_security_group_ids = [var.worker_sg_id]
  key_name      = var.key_name

  user_data = templatefile("${path.module}/k8s-worker.sh", {
    master_ip    = aws_instance.k8s_master[0].private_ip
    worker_index = count.index + 1
  })

  # Workers depend on master being created, but will poll for readiness via HTTP
  depends_on = [aws_instance.k8s_master]

  tags = {
    Name = "k8s-worker-${count.index + 1}"
  }
}
