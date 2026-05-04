# ----------------------------------------------------
# 1. Secure VPC Config (Checkov standard)
# ----------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "mern-secure-vpc"
  }
}

# (Optional Checkov fix): Enabling VPC Flow logs
resource "aws_flow_log" "vpc_flow_log" {
  log_destination      = aws_s3_bucket.flow_logs.arn
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.main.id
}

# ----------------------------------------------------
# 2. Secure S3 Bucket Config (Checkov standards)
# ----------------------------------------------------
resource "aws_s3_bucket" "app_data" {
  bucket = "mern-engine-secure-data-storage"
}

# Fix: Ensure S3 bucket has public access strictly blocked
resource "aws_s3_bucket_public_access_block" "app_data_pab" {
  bucket                  = aws_s3_bucket.app_data.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# Fix: Ensure versioning is enabled for disaster recovery
resource "aws_s3_bucket_versioning" "app_data_versioning" {
  bucket = aws_s3_bucket.app_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Fix: Ensure encryption at rest is enforced
resource "aws_s3_bucket_server_side_encryption_configuration" "app_data_encryption" {
  bucket = aws_s3_bucket.app_data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket specifically for flow logs
resource "aws_s3_bucket" "flow_logs" {
  bucket = "mern-vpc-flow-logs-storage"
}
resource "aws_s3_bucket_public_access_block" "flow_logs_pab" {
  bucket                  = aws_s3_bucket.flow_logs.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# ----------------------------------------------------
# 3. Secure Security Group
# ----------------------------------------------------
resource "aws_security_group" "web_sg" {
  name        = "mern-web-sg"
  description = "Security group for MERN stack"
  vpc_id      = aws_vpc.main.id

  # Fix: NEVER open port 22 to 0.0.0.0/0 (SSH). Narrowed to a trusted internal ingress.
  ingress {
    description = "Allow SSH from internal corporate network only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"] 
  }

  ingress {
    description = "Allow HTTPS traffic from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ----------------------------------------------------
# 4. Secure EC2 Instance
# ----------------------------------------------------
resource "aws_instance" "app_server" {
  ami           = "ami-0c55b159cbfafe1f0" # Example Amazon Linux 2 AMI
  instance_type = "t2.micro"
  
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  
  # Fix: Enforce IMDSv2 metadata service to prevent SSRF vulnerabilities
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # Forces IMDSv2
    http_put_response_hop_limit = 1
  }

  # Fix: Encrypt root block device
  root_block_device {
    encrypted = true
  }

  # Fix: Enable EBS optimization
  ebs_optimized = true

  tags = {
    Name = "MERN-App-Server"
  }
}
