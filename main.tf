#Create an EKS cluster instance in the same VPC as your database server
#Ensure your built container image contains an arbitrary file called “wizexercise.txt” with some content

#Build and host a container image for your web application*

#Deploy your container-based web application to the EKS cluster

#TODO Configure your EKS cluster to grant cluster-admin privileges to your web application container(s)

#TODO Ensure your web application authenticates to your database server (connection strings are a common approach)
#TODO Allow public internet traffic to your web application using service type loadbalancer


terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.40.0"
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


resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "eks_subnet_a" {
  vpc_id     = aws_vpc.eks_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-west-1a"
  tags = {
    Name = "eks_subnet_a"
  }
}

resource "aws_subnet" "eks_subnet_b" {
  vpc_id     = aws_vpc.eks_vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-west-1b"
  tags = {
    Name = "eks_subnet_b"
  }
}

resource "aws_internet_gateway" "eks_igw" {
  vpc_id = aws_vpc.eks_vpc.id
  tags = {
    Name = "eks_igw"
  }
}

resource "aws_route_table" "eks_route_table" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_igw.id
  }

  tags = {
    Name = "eks_route_table"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.eks_subnet_a.id
  route_table_id = aws_route_table.eks_route_table.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.eks_subnet_b.id
  route_table_id = aws_route_table.eks_route_table.id
}

resource "eks" "wizdemoeks" {
  source          = "terraform-aws-modules/eks/aws"
  cluster_name    = "my-eks-cluster"
  cluster_version = "1.21"
  subnets         = [aws_subnet.eks_subnet_a.id, 
                        aws_subnet.eks_subnet_b.id]
  vpc_id          = aws_vpc.eks_vpc.id

  node_groups = {
    eks_nodes = {
      desired_capacity = 2
      max_capacity     = 3
      min_capacity     = 1

      instance_type = "t2.micro"

      key_name = "existing_wizdemokeypair"  # Ensure you have a valid EC2 key pair

      additional_tags = {
        Name = "eks_nodes"
      }
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
