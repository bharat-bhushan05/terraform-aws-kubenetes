output "key_name" {
  value = aws_key_pair.k8s_key_pair.key_name
}

output "private_key_pem" {
  value     = tls_private_key.k8s_key.private_key_pem
  sensitive = true
}
