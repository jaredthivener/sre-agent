# ── CloudWatch log groups ─────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "agent" {
  name              = "/sre-agent/agent"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "langfuse" {
  name              = "/sre-agent/langfuse"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "metrics" {
  name              = "/sre-agent/metrics"
  retention_in_days = var.log_retention_days
}

# ── CloudWatch dashboard ──────────────────────────────────────────────────────

resource "aws_cloudwatch_dashboard" "sre_agent" {
  dashboard_name = "${var.app_name}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric",
        x      = 0,
        y = 0,
        width = 12,
        height = 6
        properties = {
          title  = "Investigation Queue Depth"
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "${var.app_name}-investigations"],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "${var.app_name}-investigations-dlq"],
          ]
          period = 60, stat = "Sum", view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "API Gateway Webhook Requests"
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiId", "REPLACE_API_ID"],
            ["AWS/ApiGateway", "4xx", "ApiId", "REPLACE_API_ID"],
            ["AWS/ApiGateway", "5xx", "ApiId", "REPLACE_API_ID"],
          ]
          period = 60, stat = "Sum", view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0, y = 6, width = 12, height = 6
        properties = {
          title  = "ECS Agent CPU & Memory"
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", var.app_name, "ServiceName", var.app_name],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", var.app_name, "ServiceName", var.app_name],
          ]
          period = 60; stat = "Average"; view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12, y = 6, width = 12, height = 6
        properties = {
          title   = "Investigation Duration (ADOT EMF)"
          metrics = [["SREAgent", "investigation_duration_seconds", "service.name", "sre-agent"]]
          period  = 300; stat = "p99"; view = "timeSeries"
        }
      }
    ]
  })
}

# ── CloudTrail — management event audit ──────────────────────────────────────

resource "aws_s3_bucket" "cloudtrail" {
  bucket        = var.cloudtrail_s3_bucket_name
  force_destroy = false
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    id     = "expire-old-trails"
    status = "Enabled"
    expiration { days = 365 }
    noncurrent_version_expiration { noncurrent_days = 30 }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "cloudtrail_bucket" {
  statement {
    sid     = "AWSCloudTrailAclCheck"
    effect  = "Allow"
    actions = ["s3:GetBucketAcl"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    resources = [aws_s3_bucket.cloudtrail.arn]
  }

  statement {
    sid     = "AWSCloudTrailWrite"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    resources = ["${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${var.aws_account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket.json
}

resource "aws_cloudtrail" "main" {
  name                          = "${var.app_name}-audit"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  # Management events only (control-plane API calls — what the SRE agent looks up during investigations)
  event_selector {
    read_write_type           = "All"
    include_management_events = true

    # Exclude high-volume S3 data events to keep costs manageable
    data_resource {
      type   = "AWS::S3::Object"
      values = []
    }
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail]
  tags       = { Name = "${var.app_name}-cloudtrail" }
}
