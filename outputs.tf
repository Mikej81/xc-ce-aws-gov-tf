output "site_name" {
  description = "F5 XC Secure Mesh Site name"
  value       = volterra_securemesh_site_v2.this.name
}

output "site_token" {
  description = "Registration token (valid 24 hours)"
  value       = local.site_token
  sensitive   = true
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.ce.id
}

output "slo_private_ip" {
  description = "SLO (outside) private IP"
  value       = aws_network_interface.slo.private_ip
}

output "sli_private_ip" {
  description = "SLI (inside) private IP"
  value       = aws_network_interface.sli.private_ip
}

output "slo_public_ip" {
  description = "SLO public IP (Elastic IP)"
  value       = var.create_eip ? aws_eip.slo[0].public_ip : null
}

output "ami_id" {
  description = "CE AMI ID used for the instance"
  value       = local.ce_ami_id
}

output "test_vm_private_ip" {
  description = "Test VM private IP on the inside subnet"
  value       = var.deploy_test_vm ? aws_network_interface.test_vm[0].private_ip : null
}

output "test_vm_instance_id" {
  description = "Test VM EC2 instance ID"
  value       = var.deploy_test_vm ? aws_instance.test_vm[0].id : null
}
