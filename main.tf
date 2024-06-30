#Create an EKS cluster instance in the same VPC as your database server
#Ensure your built container image contains an arbitrary file called wizexercise.txt with some content

#Build and host a container image for your web application

#Deploy your container-based web application to the EKS cluster

#TODO Node instances to be associated with existing pem keyfile and open SSH port
#TODO Configure your EKS cluster to grant cluster-admin privileges to your web application container(s)
#TODO Allow public internet traffic to your web application using service type loadbalancer


terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      #version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.4.3"
    }
  }
  required_version = ">= 1.1.0"
}

provider "aws" {
  region = "eu-west-1"
  access_key = "AKIARATHADOVEYTEQYWI"
  secret_key = "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"
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "4.0.0"

  name = "wiz-vpc"
  cidr = "10.0.0.0/16"

  azs             = data.aws_availability_zones.available.names
  private_subnets = ["10.0.0.0/22", "10.0.4.0/22", "10.0.8.0/22"]
  public_subnets  = ["10.0.100.0/22", "10.0.104.0/22", "10.0.108.0/22"]

  enable_nat_gateway = true
  single_nat_gateway = true
  enable_vpn_gateway = true

  public_subnet_tags = {
    "kubernetes.io/cluster/wiz-cluster" = "shared"
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/cluster/wiz-cluster" = "shared"
    "kubernetes.io/role/internal-elb" = "1"
  }
}


locals {
  vpc_id              = module.vpc.vpc_id
  vpc_cidr            = module.vpc.vpc_cidr_block
  public_subnets_ids  = module.vpc.public_subnets
  private_subnets_ids = module.vpc.private_subnets
  subnets_ids         = concat(local.public_subnets_ids, local.private_subnets_ids)
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# EKS CLUSTERS

################
#  EKS MODULE  #
################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  cluster_name    = "wiz-cluster"
  cluster_version = "1.24"

  cluster_endpoint_public_access = true
  vpc_id                   = local.vpc_id
  subnet_ids               = local.private_subnets_ids
  control_plane_subnet_ids = local.private_subnets_ids
  # kubeconfig_output_path = "~/.kube/"

  # EKS Managed Node Group(s)
  eks_managed_node_group_defaults = {
    ami_type                   = "AL2_x86_64"
    instance_types             = ["t2.micro"]
    iam_role_attach_cni_policy = true
  }

  eks_managed_node_groups = {
    wiz_node_wg = {
      min_size     = 1
      max_size     = 3
      desired_size = 2
    }
  }

}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}
data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

resource "null_resource" "wiz"{
  depends_on = [module.eks]
  provisioner "local-exec" {
    command = "aws eks --region eu-west-1  update-kubeconfig --name $AWS_CLUSTER_NAME"
    environment = {
      AWS_CLUSTER_NAME = "wiz-cluster"
    }
  }
}

data "aws_iam_policy_document" "eks_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

################################
#  ROLES FOR SERVICE ACCOUNTS  #
################################

module "vpc_cni_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name_prefix      = "VPC-CNI-IRSA"
  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }
}




# Create an ECR repository
resource "aws_ecr_repository" "app_ecr_repo" {
  name = "app-repo"
}

resource "aws_ecr_lifecycle_policy" "default_policy" {
  repository = aws_ecr_repository.app_ecr_repo.name
	

	  policy = <<EOF
	{
	    "rules": [
	        {
	            "rulePriority": 1,
	            "description": "Keep only the last 1 untagged images.",
	            "selection": {
	                "tagStatus": "untagged",
	                "countType": "imageCountMoreThan",
	                "countNumber": 1
	            },
	            "action": {
	                "type": "expire"
	            }
	        }
	    ]
	}
	EOF
}

# Provision the Kubernetes cluster
# resource "null_resource" "provision_cluster" {
#   provisioner "local-exec" {
#      curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
#      chmod +x kubectl
#      mv kubectl /usr/local/bin/
#   }
# }

# provider "kubernetes" {
#   config_path    = "~/.kube/config"
#   config_context = "aws"
# }

resource "kubernetes_deployment" "tasky-webapp" {
  metadata {
    name = "tasky-webapp"
    labels = {
      app = "tasky-webapp"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "tasky-webapp"
      }
    }

    template {
      metadata {
        labels = {
          app = "tasky-webapp"
        }
      }

      spec {
        container {
          image = "070009232298.dkr.ecr.eu-west-1.amazonaws.com/tasky_webapp:latest"
          name  = "tasky-webapp"

          port {
            container_port = 8081
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "tasky-webapp-svc" {
  metadata {
    name = "tasky-webapp-svc"
  }

  spec {
    selector = {
      app = "tasky-webapp"
    }

    port {
      port        = 80
      target_port = 8081
    }

    type = "LoadBalancer"
  }
}


resource "aws_iam_role" "eks_role" {
  name               = "eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_role.name
}

resource "aws_iam_role_policy_attachment" "eks_service_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks_role.name
}

output "cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks.cluster_id
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "EKS cluster security group ID"
  value       = module.eks.cluster_security_group_id
}

output "load_balancer_hostname" {
  value = kubernetes_service.tasky-webapp-svc.status.0.load_balancer.0.ingress.0.hostname
}
