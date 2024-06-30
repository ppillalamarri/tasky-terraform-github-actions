# Initialize AWS Provider
provider "aws" {
  region = "us-east-1"
  access_key = "AKIARATHADOVEYTEQYWI"
  secret_key = "uuIl8NxNJAFVu7/VXLYKH0zmhrFXoRn9APXB8I6r"
}



# EKS Cluster
#resource "aws_eks_cluster" "example" {
#  name     = "example-cluster"
#  role_arn = aws_iam_role.eks_cluster.arn

#  vpc_config {
#    subnet_ids = aws_subnet.example.*.id
#  }
#}

# IAM Role for EKS Cluster
resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

# Attach Policies to EKS Cluster Role
resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# EKS Node Group
resource "aws_eks_node_group" "example" {
  cluster_name    = aws_eks_cluster.example.name
  node_group_name = "example-node-group"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = aws_subnet.example.*.id

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }
}

# IAM Role for EKS Node Group
resource "aws_iam_role" "eks_node" {
  name = "eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# Attach Policies to EKS Node Role
resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node.name
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node.name
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node.name
}

# VPC and Subnets
resource "aws_subnet" "example" {
  count = 3

  vpc_id            = aws_vpc.example.id
  cidr_block        = cidrsubnet(aws_vpc.example.cidr_block, 8, count.index)
  availability_zone = element(["us-east-1a", "us-east-1b", "us-east-1c"], count.index)
}

resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"
}

# Retrieve EKS cluster authentication token
data "aws_eks_cluster_auth" "example" {
  name = aws_eks_cluster.example.name
}

# Output the EKS cluster endpoint for debugging
output "eks_cluster_endpoint" {
  value = aws_eks_cluster.example.endpoint
}

# Output the Kubernetes cluster CA certificate for debugging
output "eks_cluster_ca_certificate" {
  value = aws_eks_cluster.example.certificate_authority.0.data
}

#Creates security groups to allow SSH from the public internet and database traffic within the VPC.
#Creates an IAM role with ec2:* permissions and attaches it to the EC2 instance.
#Launches an EC2 instance with MongoDB installed and configured with authentication.
#Outputs the instance IP and MongoDB connection string.

# Configure a security group to allow SSH to the VM from the public internet


# Define a security group for SSH access
resource "aws_security_group" "ssh" {
  name        = "ssh_security_group"
  description = "Allow SSH inbound traffic"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ssh_security_group"
  }
}

# Define a security group for HTTP access
resource "aws_security_group" "http" {
  name        = "http_security_group"
  description = "Allow HTTP inbound traffic"

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "http_security_group"
  }
}

# Configure an instance profile to the VM and add the permission “ec2:*” as a custom policy

resource "aws_iam_role" "ec2_role" {
  name = "ec2_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "ec2_policy" {
  name = "ec2_policy"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "ec2:*"
        Effect = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2_instance_profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_instance" "mongodb" {
  #ami                    = "ami-08ba52a61087f1bd6"  # Choose an appropriate Amazon Linux 2 AMI
  ami = "ami-0bb323ae9abcae1a0" # amzn2-ami-kernel-5.10-hvm-2.0.20240620.0-x86_64-gp2  
  instance_type         = "t2.micro"
  key_name              = var.key_name

  # Associate the security groups with the instance
  vpc_security_group_ids = [
    aws_security_group.ssh.id,
    aws_security_group.http.id
  ]

  user_data = <<-EOF
              #!/bin/bash
              sudo tee -a /etc/yum.repos.d/mongodb-org-4.4.repo << EOM
              [mongodb-org-6.0]
              name=MongoDB Repository
              baseurl=https://repo.mongodb.org/yum/amazon/2/mongodb-org/6.0/x86_64/
              gpgcheck=1
              enabled=1
              gpgkey=https://www.mongodb.org/static/pgp/server-6.0.asc
              EOM

              sudo yum install -y mongodb-org
              sudo systemctl start mongod
              sudo systemctl enable mongod
              # Setup MongoDB admin user
              #sudo mongosh admin --eval 'db.createUser({user:"admin", pwd:"password", roles:[{role:"root", db:"admin"}]})'

              # Configure MongoDB authentication
              #sudo sed -i 's/#security:/security:\\n  authorization: "enabled"/' /etc/mongod.conf
              #sudo systemctl restart mongod
              EOF

  tags = {
    Name = "MongoDBServer"
  }
}

# Kubernetes Provider
provider "kubernetes" {
  host                   = aws_eks_cluster.example.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.example.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.example.token

}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  cluster_name    = "example-cluster"
  cluster_version = "1.20"
  #subnets         = module.vpc.private_subnets
  #subnets         = aws_subnet.example.*.id
  #vpc_id          = module.vpc.vpc_id
  vpc_id          = aws_vpc.example.id
  #kubeconfig_output_path = "~/.kube/"
  #role_arn = aws_iam_role.eks_cluster.arn
  node_groups = {
    first = {
      desired_capacity = 2
      max_capacity =  3
      min_capacity = 1
      instance_type = "t3.small"
    }
  }
}

resource "null_resource" "example"{
  depends_on = [module.eks]
  provisioner "local-exec" {
    command = "aws eks --region us-east-1  update-kubeconfig --name $AWS_CLUSTER_NAME"
    environment = {
      AWS_CLUSTER_NAME = "example-cluster"
    }
  }
}

# Kubernetes Deployment
resource "kubernetes_deployment" "example" {
  metadata {
    name = "example-deployment"
    labels = {
      app = "example-app"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "example-app"
      }
    }

    template {
      metadata {
        labels = {
          app = "example-app"
        }
      }

      spec {
        container {
          image = "070009232298.dkr.ecr.eu-west-1.amazonaws.com/app-repo_taskywebapp:latest"
          name  = "example-container"

          port {
            container_port = 80
          }
        }
      }
    }
  }
}


# Kubernetes Service
resource "kubernetes_service" "example" {
  metadata {
    name = "example-service"
  }

  spec {
    selector = {
      app = "example-app"
    }

    port {
      port        = 80
      target_port = 8080
    }

    type = "LoadBalancer"
  }
}

output "instance_ip" {
  value = aws_instance.mongodb.public_ip
}

output "connection_string" {
  value = "mongodb://admin:password@${aws_instance.mongodb.public_ip}:27017/admin"
}

output "load_balancer_hostname" {
  value = kubernetes_service.example.status.0.load_balancer.0.ingress.0.hostname
}
