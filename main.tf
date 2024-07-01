# Initialize AWS Provider
provider "aws" {
  region = "us-east-1"
  access_key = "AKIA6ODUZDIMWYJTBJUZ"
  secret_key = "q1hVM1Ntzsg22JGGaTcYhbElBf7DyaYrW8fou0Ng"
  
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

resource "aws_security_group" "mdbport" {
  name        = "mdbport_security_group"
  description = "Allow mdbport inbound traffic"

  ingress {
    description = "mdbport"
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mdbport_security_group"
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
  ami = "ami-0195204d5dce06d99" # amzn2-ami-kernel-5.10-hvm-2.0.20240620.0-x86_64-gp2  
  instance_type         = "t2.micro"
  key_name              = var.key_name

  # Associate the security groups with the instance
  vpc_security_group_ids = [
    aws_security_group.ssh.id,
    aws_security_group.http.id,
    aws_security_group.mdbport.id
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
              mongosh admin --eval 'db.createUser({user:"admin", pwd:"password", roles:[{role:"root", db:"admin"}]})'

              # Configure MongoDB authentication
              #sudo sed -i 's/#security:/security:\\n  authorization: "enabled"/' /etc/mongod.conf
              #sudo systemctl restart mongod

              # Create the backup script
              sudo touch /usr/local/bin/mongodb_backup.sh
              sudo chmod 777 /usr/local/bin/mongodb_backup.sh
              echo '#!/bin/bash
              sudo mkdir -p /var/backups/mongobackup
              sudo mongodump --out /var/backups/mongobackup
              aws s3 cp /var/backups/mongobackup s3://mywizdemobucket/$(date +\%F-\%T) --recursive' > /usr/local/bin/mongodb_backup.sh
              chmod +x /usr/local/bin/mongodb_backup.sh
              
              # Schedule the backup script using cron
              echo '0 2 * * * /usr/local/bin/mongodb_backup.sh' > /etc/cron.d/mongodb_backup

              EOF

  tags = {
    Name = "MongoDBServer"
  }
}



output "connection_string" {
  value = "mongodb://admin:password@${aws_instance.mongodb.public_ip}:27017/admin"
}

