# -----------------------------------------------------------------------------
# F5 XC API
# -----------------------------------------------------------------------------

variable "f5xc_api_url" {
  type        = string
  description = "F5 XC tenant API URL"
}

variable "f5xc_api_p12_file" {
  type        = string
  description = "Path to the F5 XC API credentials P12 file (password via VES_P12_PASSWORD env var)"
}

variable "f5xc_api_token" {
  type        = string
  description = "F5 XC API token for Day-2 provisioners (set public IP, configure segments). If provided, used instead of P12 for API calls."
  default     = null
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Network Segment (Day-2)
# -----------------------------------------------------------------------------

variable "segment_name" {
  type        = string
  description = "Network segment to assign to the SLI interface after site registration. If null, no segment is configured."
  default     = null
}

# -----------------------------------------------------------------------------
# AWS
# -----------------------------------------------------------------------------

variable "aws_region" {
  type        = string
  description = "AWS GovCloud region"
  default     = "us-gov-west-1"
}

variable "aws_profile" {
  type        = string
  description = "AWS CLI profile name (null = use default chain)"
  default     = null
}

variable "vpc_id" {
  type        = string
  description = "Existing VPC ID. If null, a new VPC is created using vpc_cidr."
  default     = null
}

variable "outside_subnet_id" {
  type        = string
  description = "SLO (outside) subnet ID. If null, a new subnet is created using outside_subnet_cidr."
  default     = null
}

variable "inside_subnet_id" {
  type        = string
  description = "SLI (inside) subnet ID. If null, a new subnet is created using inside_subnet_cidr."
  default     = null
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC (only used when creating a new VPC)"
  default     = "192.168.0.0/16"
}

variable "outside_subnet_cidr" {
  type        = string
  description = "CIDR for the SLO subnet (only used when creating a new subnet)"
  default     = "192.168.1.0/24"
}

variable "inside_subnet_cidr" {
  type        = string
  description = "CIDR for the SLI subnet (only used when creating a new subnet)"
  default     = "192.168.2.0/24"
}

variable "az" {
  type        = string
  description = "Availability zone for new subnets. If null, AWS selects automatically."
  default     = null
}

# -----------------------------------------------------------------------------
# CE Image
#
# Provide EITHER ami_id (if you already have an AMI) OR ce_image_download_url
# + s3_bucket_name to import the image automatically.
# The download URL comes from the F5 XC Console: create an SMSv2 site,
# then click ... > Copy Image Name.
# -----------------------------------------------------------------------------

variable "ami_id" {
  type        = string
  description = "F5 XC CE AMI ID. If null and ce_image_download_url is set, the image will be imported automatically."
  default     = null
}

variable "ce_image_download_url" {
  type        = string
  description = "F5 XC CE image download URL from Console. Used only when ami_id is null."
  default     = "https://vesio.blob.core.windows.net/releases/rhel/9/x86_64/images/securemeshV2/azure/f5xc-ce-9.2024.44-20250102054713.vhd.gz"
}

variable "ce_image_file" {
  type        = string
  description = "Path to a pre-downloaded CE image file. When set, skips downloading from ce_image_download_url."
  default     = null
}

variable "s3_bucket_name" {
  type        = string
  description = "S3 bucket for staging CE image import. Required when using ce_image_download_url."
  default     = null
}

# -----------------------------------------------------------------------------
# Site
# -----------------------------------------------------------------------------

variable "site_name" {
  type        = string
  description = "F5 XC Secure Mesh Site name (DNS-1035: lowercase, alphanumeric, hyphens)"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.site_name))
    error_message = "Must be DNS-1035 compliant: start with letter, end alphanumeric, lowercase + hyphens only."
  }
}

variable "site_description" {
  type    = string
  default = "F5 XC SMSv2 CE in AWS GovCloud"
}

# -----------------------------------------------------------------------------
# EC2
# -----------------------------------------------------------------------------

variable "instance_type" {
  type        = string
  description = "EC2 instance type (min 8 vCPU / 32 GB RAM)"
  default     = "m5.2xlarge"
}

variable "disk_size_gb" {
  type    = number
  default = 128
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for CE admin access"
  sensitive   = true
}

variable "enable_etcd_fix" {
  type        = bool
  description = "TEMPORARY: Enable cloud-init workaround for VPM bug that leaves ETCD_IMAGE blank in /etc/default/etcd-member. Disable once the CE image is patched."
  default     = true
}

variable "ce_etcd_image" {
  type        = string
  description = "TEMPORARY: Etcd container image for the etcd-member fix. Only used when enable_etcd_fix = true."
  default     = "200853955439.dkr.ecr.us-gov-west-1.amazonaws.com/etcd@sha256:5e084d6d22ee0a3571e3f755b8946cad297afb05e1f3772dc0fcd1a70ae6c928"
}

# -----------------------------------------------------------------------------
# Site Mesh Group
# -----------------------------------------------------------------------------

variable "enable_site_mesh_group" {
  type        = bool
  description = "Enable site mesh group on SLO for site-to-site connectivity. Post-registration manual steps required — see README."
  default     = true
}

variable "site_mesh_label_key" {
  type        = string
  description = "Label key used by the core MCN virtual site selector to include this CE in a mesh group"
  default     = "site-mesh"
}

variable "site_mesh_label_value" {
  type        = string
  description = "Label value for mesh group membership (must match the core MCN virtual site selector)"
  default     = "global-network-mesh"
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

variable "slo_security_group_id" {
  type        = string
  description = "Existing security group ID for the SLO ENI. If null, a new SG is created with a default outbound-allow rule."
  default     = null
}

variable "sli_security_group_id" {
  type        = string
  description = "Existing security group ID for the SLI ENI. If null, a new SG is created with a default inbound-allow rule."
  default     = null
}

variable "slo_private_ip" {
  type        = string
  description = "Static SLO IP (null = DHCP)"
  default     = null
}

variable "sli_private_ip" {
  type        = string
  description = "Static SLI IP (null = DHCP)"
  default     = null
}

variable "create_eip" {
  type    = bool
  default = true
}

# -----------------------------------------------------------------------------
# Test VM
# -----------------------------------------------------------------------------

variable "deploy_test_vm" {
  type        = bool
  description = "Deploy a Ubuntu test VM on the inside (SLI) subnet for connectivity testing"
  default     = false
}

variable "test_vm_instance_type" {
  type        = string
  description = "Instance type for the test VM"
  default     = "t3.micro"
}

variable "test_vm_private_ip" {
  type        = string
  description = "Static IP for the test VM on the inside subnet (null = DHCP)"
  default     = null
}

variable "test_vm_remote_cidrs" {
  type        = list(string)
  description = "Remote inside CIDRs to route via the CE SLI interface (e.g. on-prem, Azure)"
  default     = []
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  type    = map(string)
  default = {}
}
