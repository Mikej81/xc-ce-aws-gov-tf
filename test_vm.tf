# -----------------------------------------------------------------------------
# Test VM — Ubuntu on the inside (SLI) subnet
#
# Toggle with: deploy_test_vm = true
# Routes remote CIDRs via the CE's SLI IP for cross-site connectivity testing.
# -----------------------------------------------------------------------------

data "aws_ami" "ubuntu" {
  count       = var.deploy_test_vm ? 1 : 0
  most_recent = true
  owners      = ["513442679011"] # Canonical (GovCloud)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_security_group" "test_vm" {
  count       = var.deploy_test_vm ? 1 : 0
  name        = "${local.prefix}-sg-test-vm"
  description = "Test VM - ICMP and SSH inbound, all outbound"
  vpc_id      = local.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ICMP"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.prefix}-sg-test-vm" })
}

resource "aws_network_interface" "test_vm" {
  count             = var.deploy_test_vm ? 1 : 0
  subnet_id         = local.inside_subnet_id
  security_groups   = [aws_security_group.test_vm[0].id]
  source_dest_check = false
  private_ips       = var.test_vm_private_ip != null ? [var.test_vm_private_ip] : null

  tags = merge(local.common_tags, { Name = "${local.prefix}-eni-test-vm" })
}

resource "aws_instance" "test_vm" {
  count         = var.deploy_test_vm ? 1 : 0
  ami           = data.aws_ami.ubuntu[0].id
  instance_type = var.test_vm_instance_type
  key_name      = aws_key_pair.ce.key_name

  primary_network_interface {
    network_interface_id = aws_network_interface.test_vm[0].id
  }

  user_data_base64 = length(var.test_vm_remote_cidrs) > 0 ? base64encode(templatefile("${path.module}/templates/test_vm_userdata.yaml", {
    ce_sli_ip    = aws_network_interface.sli.private_ip
    remote_cidrs = var.test_vm_remote_cidrs
  })) : ""

  tags = merge(local.common_tags, { Name = "${local.prefix}-test-vm" })

  depends_on = [
    aws_instance.ce,
  ]
}
