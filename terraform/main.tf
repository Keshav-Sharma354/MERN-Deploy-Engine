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

# Fix CKV2_AWS_12: Ensure default SG restricts all traffic
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
  # No ingress/egress rules makes it deny all
}

resource "aws_flow_log" "vpc_flow_log" {
  log_destination      = aws_s3_bucket.flow_logs.arn
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.main.id
}

# ----------------------------------------------------
# 2. Secure S3 Bucket Config (Checkov standards)
# ----------------------------------------------------

# Centralized KMS Key for S3 Encryption (Fixes CKV_AWS_145)
resource "aws_kms_key" "s3_key" {
  description             = "KMS key for S3 bucket encryption"
  enable_key_rotation     = true
}

# Logging bucket specifically for S3 access logs
# checkov:skip=CKV_AWS_144: Cross-region replication not needed for access logs
# checkov:skip=CKV_AWS_18: Access logging bucket doesn't need to log itself
# checkov:skip=CKV2_AWS_62: Event notification not required for log bucket
resource "aws_s3_bucket" "s3_access_logs" {
  bucket = "mern-s3-access-logs-storage"
}
resource "aws_s3_bucket_public_access_block" "s3_access_logs_pab" {
  bucket                  = aws_s3_bucket.s3_access_logs.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "s3_access_logs_enc" {
  bucket = aws_s3_bucket.s3_access_logs.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}
resource "aws_s3_bucket_versioning" "s3_access_logs_versioning" {
  bucket = aws_s3_bucket.s3_access_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_lifecycle_configuration" "s3_access_logs_lifecycle" {
  bucket = aws_s3_bucket.s3_access_logs.id
  rule {
    id     = "archive"
    status = "Enabled"
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

# Flow logs bucket
# checkov:skip=CKV_AWS_144: Cross-region replication not needed for flow logs
# checkov:skip=CKV2_AWS_62: Event notification not required for log bucket
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
resource "aws_s3_bucket_versioning" "flow_logs_versioning" {
  # Fix CKV_AWS_21
  bucket = aws_s3_bucket.flow_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_logging" "flow_logs_logging" {
  # Fix CKV_AWS_18
  bucket        = aws_s3_bucket.flow_logs.id
  target_bucket = aws_s3_bucket.s3_access_logs.id
  target_prefix = "flow-logs/"
}
resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs_enc" {
  bucket = aws_s3_bucket.flow_logs.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}
resource "aws_s3_bucket_lifecycle_configuration" "flow_logs_lifecycle" {
  # Fix CKV2_AWS_61
  bucket = aws_s3_bucket.flow_logs.id
  rule {
    id     = "cleanup"
    status = "Enabled"
    expiration {
      days = 90
    }
  }
}

# Main App Data Bucket
# checkov:skip=CKV_AWS_144: Cross region replication not necessary for this architecture
# checkov:skip=CKV2_AWS_62: Event notification not utilized natively in the backend
resource "aws_s3_bucket" "app_data" {
  bucket = "mern-engine-secure-data-storage"
}
resource "aws_s3_bucket_public_access_block" "app_data_pab" {
  bucket                  = aws_s3_bucket.app_data.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_versioning" "app_data_versioning" {
  bucket = aws_s3_bucket.app_data.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_logging" "app_data_logging" {
  # Fix CKV_AWS_18
  bucket        = aws_s3_bucket.app_data.id
  target_bucket = aws_s3_bucket.s3_access_logs.id
  target_prefix = "app-data/"
}
resource "aws_s3_bucket_server_side_encryption_configuration" "app_data_encryption" {
  bucket = aws_s3_bucket.app_data.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}
resource "aws_s3_bucket_lifecycle_configuration" "app_data_lifecycle" {
  # Fix CKV2_AWS_61
  bucket = aws_s3_bucket.app_data.id
  rule {
    id     = "tiering"
    status = "Enabled"
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

# ----------------------------------------------------
# 3. Secure Security Group
# ----------------------------------------------------
resource "aws_security_group" "web_sg" {
  name        = "mern-web-sg"
  description = "Security group for MERN stack"
  vpc_id      = aws_vpc.main.id

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
# Fix CKV2_AWS_41: Ensure IAM role is attached
resource "aws_iam_role" "ec2_role" {
  name = "mern_ec2_role"
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

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "mern_ec2_profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_instance" "app_server" {
  ami           = "ami-0c55b159cbfafe1f0" 
  instance_type = "t2.micro"
  
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name # Attach IAM Role
  
  monitoring = true # Fix CKV_AWS_126: Detailed Monitoring

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" 
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted = true
  }

  ebs_optimized = true

  tags = {
    Name = "MERN-App-Server"
  }
}
