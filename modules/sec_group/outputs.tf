output "master_sg_id" {
  value = aws_security_group.k8s_master.id
}

output "worker_sg_id" {
  value = aws_security_group.k8s_worker.id
}
