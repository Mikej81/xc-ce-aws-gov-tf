# -----------------------------------------------------------------------------
# AWS Infrastructure — F5 XC SMSv2 CE in AWS GovCloud
# -----------------------------------------------------------------------------

resource "random_id" "suffix" {
  byte_length = 2
}

locals {
  prefix = "${var.site_name}-${random_id.suffix.hex}"
  common_tags = merge(var.tags, {
    source                                   = "terraform"
    site_name                                = var.site_name
    "ves-io-site-name"                       = local.prefix
    "kubernetes.io/cluster/${local.prefix}"   = "Owned"
  })
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_vpc" "this" {
  id = var.vpc_id
}

data "aws_subnet" "outside" {
  id = var.outside_subnet_id
}

data "aws_subnet" "inside" {
  id = var.inside_subnet_id
}

data "aws_route_table" "inside" {
  subnet_id = var.inside_subnet_id
}

# Default route on the inside subnet via CE SLI ENI.
# Required for segment traffic — workloads on the inside subnet need the CE
# as the next hop for cross-site and on-prem traffic.
resource "aws_route" "sli_default_via_ce" {
  route_table_id         = data.aws_route_table.inside.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_network_interface.sli.id
}

# -----------------------------------------------------------------------------
# SSH Key Pair
# -----------------------------------------------------------------------------

resource "aws_key_pair" "ce" {
  key_name   = "${local.prefix}-key"
  public_key = var.ssh_public_key
  tags       = local.common_tags
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------

resource "aws_security_group" "slo" {
  count       = var.slo_security_group_id == null ? 1 : 0
  name        = "${local.prefix}-sg-slo"
  description = "SLO (outside) security group for F5 XC CE"
  vpc_id      = var.vpc_id

  # CE-to-CE IPsec — Site Mesh Group (bidirectional)
  ingress {
    description = "IKE (IPsec key exchange)"
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "NAT-T (IPsec NAT traversal)"
    from_port   = 4500
    to_port     = 4500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ESP (IPsec encrypted payload)"
    from_port   = 0
    to_port     = 0
    protocol    = "50"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # CE-to-CE IP-in-IP — DC Cluster Group
  ingress {
    description = "IP-in-IP tunnel (DC Cluster Group)"
    from_port   = 6080
    to_port     = 6080
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.prefix}-sg-slo" })
}

resource "aws_security_group" "sli" {
  count       = var.sli_security_group_id == null ? 1 : 0
  name        = "${local.prefix}-sg-sli"
  description = "SLI (inside) security group for F5 XC CE"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow all inbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.prefix}-sg-sli" })
}

locals {
  slo_sg_id = coalesce(var.slo_security_group_id, try(aws_security_group.slo[0].id, null))
  sli_sg_id = coalesce(var.sli_security_group_id, try(aws_security_group.sli[0].id, null))
}

# -----------------------------------------------------------------------------
# Network Interfaces — SLO (eth0) then SLI (eth1)
# -----------------------------------------------------------------------------

resource "aws_network_interface" "slo" {
  subnet_id         = var.outside_subnet_id
  security_groups   = [local.slo_sg_id]
  source_dest_check = false
  private_ips       = var.slo_private_ip != null ? [var.slo_private_ip] : null

  tags = merge(local.common_tags, { Name = "${local.prefix}-eni-slo" })
}

resource "aws_network_interface" "sli" {
  subnet_id         = var.inside_subnet_id
  security_groups   = [local.sli_sg_id]
  source_dest_check = false
  private_ips       = var.sli_private_ip != null ? [var.sli_private_ip] : null

  tags = merge(local.common_tags, { Name = "${local.prefix}-eni-sli" })
}

# -----------------------------------------------------------------------------
# Elastic IP (optional)
# -----------------------------------------------------------------------------

resource "aws_eip" "slo" {
  count  = var.create_eip ? 1 : 0
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${local.prefix}-eip-slo" })
}

resource "aws_eip_association" "slo" {
  count                = var.create_eip ? 1 : 0
  allocation_id        = aws_eip.slo[0].id
  network_interface_id = aws_network_interface.slo.id
}

# -----------------------------------------------------------------------------
# IAM Role + Instance Profile
#
# Minimum permissions required by F5 XC CE for cloud discovery.
# -----------------------------------------------------------------------------

resource "aws_iam_role" "ce" {
  name = "${local.prefix}-ce-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "ce" {
  name = "${local.prefix}-ce-policy"
  role = aws_iam_role.ce.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:DescribeInstances",
        "ec2:DescribeTags",
        "autoscaling:DescribeAutoScalingInstances",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_instance_profile" "ce" {
  name = "${local.prefix}-ce-profile"
  role = aws_iam_role.ce.name
  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# CE EC2 Instance
# -----------------------------------------------------------------------------

resource "aws_instance" "ce" {
  ami                  = local.ce_ami_id
  instance_type        = var.instance_type
  key_name             = aws_key_pair.ce.key_name
  iam_instance_profile = aws_iam_instance_profile.ce.name
  user_data_base64     = base64encode(local.ce_user_data)

  primary_network_interface {
    network_interface_id = aws_network_interface.slo.id
  }

  root_block_device {
    volume_size = var.disk_size_gb
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, { Name = local.prefix })

  # source_dest_check is managed per-ENI, not at instance level with multi-NIC
  lifecycle {
    ignore_changes = [source_dest_check]
  }

  depends_on = [
    aws_eip_association.slo,
  ]
}

resource "aws_network_interface_attachment" "sli" {
  instance_id          = aws_instance.ce.id
  network_interface_id = aws_network_interface.sli.id
  device_index         = 1
}
