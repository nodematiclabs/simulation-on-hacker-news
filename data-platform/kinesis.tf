provider "aws" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

variable "db_username" {
  type = string
  description = "A username for accessing the Redshift cluster"
}

variable "db_password" {
  type = string
  description = "A password for securing the Redshift cluster"
  sensitive = true
}

resource "aws_default_vpc" "default" {}

resource "aws_redshift_cluster" "on_hacker_news" {
  cluster_identifier     = "on-hacker-news"
  database_name          = "on_hacker_news"
  master_username        = var.db_username
  master_password        = var.db_password
  node_type              = "dc2.large"
  cluster_type           = "single-node"
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.allow_redshift.id]
}

resource "aws_kinesis_firehose_delivery_stream" "on_hacker_news" {
  name        = "on-hacker-news"
  destination = "redshift"

  s3_configuration {
    role_arn        = aws_iam_role.on_hacker_news_firehose.arn
    bucket_arn      = aws_s3_bucket.on_hacker_news.arn
    prefix          = "intermediate"
    buffer_size     = 1
    buffer_interval = 60

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.on_hacker_news.name
      log_stream_name = aws_cloudwatch_log_stream.s3.name
    }
  }

  redshift_configuration {
    role_arn           = aws_iam_role.on_hacker_news_firehose.arn
    cluster_jdbcurl    = "jdbc:redshift://${aws_redshift_cluster.on_hacker_news.endpoint}/${aws_redshift_cluster.on_hacker_news.database_name}"
    username           = var.db_username
    password           = var.db_password
    data_table_name    = "on_hacker_news"
    copy_options       = "json 'auto'"
    s3_backup_mode     = "Enabled"

    s3_backup_configuration {
      role_arn        = aws_iam_role.on_hacker_news_firehose.arn
      bucket_arn      = aws_s3_bucket.on_hacker_news.arn
      prefix          = "backup"
      buffer_size     = 1
      buffer_interval = 60
    }

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.on_hacker_news.name
      log_stream_name = aws_cloudwatch_log_stream.redshift.name
    }
  }
}

resource "aws_s3_bucket" "on_hacker_news" {
  bucket        = "on-hacker-news"
  acl           = "private"
  force_destroy = true
}

resource "aws_cloudwatch_log_group" "on_hacker_news" {
  name = "on-hacker-news"
}

resource "aws_cloudwatch_log_stream" "s3" {
  name           = "s3"
  log_group_name = aws_cloudwatch_log_group.on_hacker_news.name
}

resource "aws_cloudwatch_log_stream" "redshift" {
  name           = "redshift"
  log_group_name = aws_cloudwatch_log_group.on_hacker_news.name
}

resource "aws_iam_role" "on_hacker_news_firehose" {
  name = "on-hacker-news-firehose"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "on_hacker_news" {
  role       = aws_iam_role.on_hacker_news_firehose.name
  policy_arn = aws_iam_policy.on_hacker_news.arn
}

resource "aws_iam_policy" "on_hacker_news" {
  name   = "on_hacker_news"
  path   = "/"
  policy = data.aws_iam_policy_document.on_hacker_news.json
}

data "aws_iam_policy_document" "on_hacker_news" {
  statement {
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:PutObject",
    ]

    resources = [
      "arn:aws:s3:::${aws_s3_bucket.on_hacker_news.bucket}",
      "arn:aws:s3:::${aws_s3_bucket.on_hacker_news.bucket}/*",
    ]
  }

  statement {
    actions = [
      "logs:PutLogEvents",
    ]

    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${aws_cloudwatch_log_group.on_hacker_news.name}:log-stream:${aws_cloudwatch_log_stream.redshift.name}",
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${aws_cloudwatch_log_group.on_hacker_news.name}:log-stream:${aws_cloudwatch_log_stream.s3.name}",
    ]
  }
}

resource "aws_security_group" "allow_redshift" {
  name   = "allow-redshift"
  vpc_id = aws_default_vpc.default.id

  ingress {
    from_port        = 5439
    to_port          = 5439
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

output "endpoint" {
  value       = aws_redshift_cluster.on_hacker_news.endpoint
  description = "The endpoint for Redshift connections"
}

output "username" {
  value       = aws_redshift_cluster.on_hacker_news.master_username
  description = "The username for Redshift connections"
}

output "password" {
  value       = aws_redshift_cluster.on_hacker_news.master_password
  description = "The password for Redshift connections"
  sensitive   = true
}

output "region" {
  value = data.aws_region.current.name
  description = "The region for AWS Firehose connections"
}