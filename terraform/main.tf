# Fetch available AWS Availability Zones (AZs) with opt-in not required
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# Generate a unique suffix for resource naming to avoid conflicts
resource "random_string" "suffix" {
  length  = 8
  special = false
}

# ✅ VPC Module - Configuring the VPC with NAT Gateway, DNS, and Subnet Tagging
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "e2ecicd-vpc-${var.environment}"
  cidr = lookup(local.vpc_cidrs, var.environment)

  # Select the first three AZs dynamically
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets = lookup(local.private_subnets, var.environment)
  public_subnets  = lookup(local.public_subnets, var.environment)

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # Tag public subnets for Kubernetes ELB
  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  # Tag private subnets for internal Kubernetes load balancing
  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

# ✅ EKS Cluster Module - Deploying an EKS Cluster with Managed Node Groups
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.21.0"

  cluster_name = local.cluster_name
  # 1.29 is in EKS "extended support" = $0.60/hr control plane (6x).
  # 1.34 is in standard support = $0.10/hr. Verified via `aws eks describe-cluster-versions`.
  cluster_version = "1.34"

  vpc_id                          = module.vpc.vpc_id
  subnet_ids                      = module.vpc.private_subnets
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # --- Cost guard for this short-lived lab ---
  # A customer-managed KMS key costs $1/month, and `terraform destroy` can only
  # SCHEDULE its deletion (7-30 day window; defaults to 30). AWS bills for the key
  # that entire time, so it would outlive the cluster and eat the whole budget.
  # Cluster secrets are still encrypted at rest with AWS-managed keys without this.
  create_kms_key            = false
  cluster_encryption_config = {}

  # Enable EKS add-ons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  # Set default configurations for EKS managed nodes
  eks_managed_node_group_defaults = {
    # EKS 1.34 does not offer Amazon Linux 2 node images; AL2023 is the current node OS.
    ami_type                   = "AL2023_x86_64_STANDARD"
    iam_role_attach_cni_policy = true
  }

  # Managed Node Group Configuration
  eks_managed_node_groups = {
    eks_nodes = {
      name = "node-group-${var.environment}"

      instance_types = [lookup(local.instance_type, var.environment)]

      min_size     = 1
      max_size     = lookup(local.desired_instance_count, var.environment)
      desired_size = lookup(local.desired_instance_count, var.environment)

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size = 50
            volume_type = "gp3"
            encrypted   = true
          }
        }
      }

      tags = {
        Environment = var.environment
        Terraform   = "true"
        Kubernetes  = "EKS"
        NodeGroup   = "managed"
      }
    }
  }
}
