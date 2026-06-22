locals {
  tags = {
    Project = var.project
    Env     = var.env
    Owner   = var.owner
  }
}

resource "aws_s3_bucket" "event_archive" {
  bucket = var.event_archive_bucket_name

  tags = local.tags
}

resource "aws_s3_bucket_versioning" "event_archive" {
  bucket = aws_s3_bucket.event_archive.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_cloudwatch_event_bus" "retail_ops" {
  name = "${var.project}-${var.env}-bus"

  tags = local.tags
}

resource "aws_sqs_queue" "inventory_events" {
  name                       = "${var.project}-${var.env}-inventory-events"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 86400

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.inventory_events_dlq.arn
    maxReceiveCount     = 3
  })

  tags = local.tags
}

resource "aws_sqs_queue" "pricing_events" {
  name                       = "${var.project}-${var.env}-pricing-events"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 86400

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.pricing_events_dlq.arn
    maxReceiveCount     = 3
  })

  tags = local.tags
}

resource "aws_dynamodb_table" "retail_operations" {
  name         = "${var.project}-${var.env}-retail-operations"
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "event_id"
  range_key = "event_timestamp"

  attribute {
    name = "event_id"
    type = "S"
  }

  attribute {
    name = "event_timestamp"
    type = "S"
  }

  tags = local.tags
}

resource "aws_sns_topic" "alerts" {
  name = "${var.project}-${var.env}-alerts"

  tags = local.tags
}
resource "aws_cloudwatch_event_rule" "inventory_events" {
  name           = "${var.project}-${var.env}-inventory-rule"
  event_bus_name = aws_cloudwatch_event_bus.retail_ops.name

  event_pattern = jsonencode({
    source      = ["retail.operations"]
    detail-type = ["inventory_event"]
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_rule" "pricing_events" {
  name           = "${var.project}-${var.env}-pricing-rule"
  event_bus_name = aws_cloudwatch_event_bus.retail_ops.name

  event_pattern = jsonencode({
    source      = ["retail.operations"]
    detail-type = ["pricing_event"]
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "inventory_queue" {
  rule           = aws_cloudwatch_event_rule.inventory_events.name
  event_bus_name = aws_cloudwatch_event_bus.retail_ops.name
  target_id      = "inventory-events-sqs"
  arn            = aws_sqs_queue.inventory_events.arn
}

resource "aws_cloudwatch_event_target" "pricing_queue" {
  rule           = aws_cloudwatch_event_rule.pricing_events.name
  event_bus_name = aws_cloudwatch_event_bus.retail_ops.name
  target_id      = "pricing-events-sqs"
  arn            = aws_sqs_queue.pricing_events.arn
}

resource "aws_sqs_queue_policy" "inventory_events" {
  queue_url = aws_sqs_queue.inventory_events.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.inventory_events.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.inventory_events.arn
          }
        }
      }
    ]
  })
}

resource "aws_sqs_queue_policy" "pricing_events" {
  queue_url = aws_sqs_queue.pricing_events.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.pricing_events.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.pricing_events.arn
          }
        }
      }
    ]
  })
}
resource "aws_iam_role" "lambda_role" {
  name = "${var.project}-${var.env}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project}-${var.env}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.retail_operations.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.event_archive.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [
          aws_sqs_queue.inventory_events.arn,
          aws_sqs_queue.pricing_events.arn
        ]
      }
    ]
  })
}

data "archive_file" "inventory_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../../../src/lambda/inventory_processor/lambda_function.py"
  output_path = "${path.module}/inventory_processor.zip"
}

data "archive_file" "pricing_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../../../src/lambda/pricing_processor/lambda_function.py"
  output_path = "${path.module}/pricing_processor.zip"
}

resource "aws_lambda_function" "inventory_processor" {
  function_name = "${var.project}-${var.env}-inventory-processor"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"

  filename         = data.archive_file.inventory_lambda_zip.output_path
  source_code_hash = data.archive_file.inventory_lambda_zip.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.retail_operations.name
      ARCHIVE_BUCKET = aws_s3_bucket.event_archive.bucket
      SNS_TOPIC_ARN  = aws_sns_topic.alerts.arn
    }
  }

  tags = local.tags
}

resource "aws_lambda_function" "pricing_processor" {
  function_name = "${var.project}-${var.env}-pricing-processor"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"

  filename         = data.archive_file.pricing_lambda_zip.output_path
  source_code_hash = data.archive_file.pricing_lambda_zip.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.retail_operations.name
      ARCHIVE_BUCKET = aws_s3_bucket.event_archive.bucket
      SNS_TOPIC_ARN  = aws_sns_topic.alerts.arn
    }
  }

  tags = local.tags
}

resource "aws_sqs_queue" "inventory_events_dlq" {
  name = "${var.project}-${var.env}-inventory-events-dlq"

  message_retention_seconds = 1209600

  tags = local.tags
}

resource "aws_sqs_queue" "pricing_events_dlq" {
  name = "${var.project}-${var.env}-pricing-events-dlq"

  message_retention_seconds = 1209600

  tags = local.tags
}

resource "aws_lambda_event_source_mapping" "inventory_sqs_trigger" {
  event_source_arn = aws_sqs_queue.inventory_events.arn
  function_name    = aws_lambda_function.inventory_processor.arn
  batch_size       = 5
}

resource "aws_lambda_event_source_mapping" "pricing_sqs_trigger" {
  event_source_arn = aws_sqs_queue.pricing_events.arn
  function_name    = aws_lambda_function.pricing_processor.arn
  batch_size       = 5
}

resource "aws_glue_catalog_database" "retail_event_operations" {
  name = "retail_event_operations_db"
}
resource "aws_glue_catalog_table" "inventory_events" {
  name          = "inventory_events"
  database_name = aws_glue_catalog_database.retail_event_operations.name
  table_type    = "EXTERNAL_TABLE"

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.event_archive.bucket}/raw/inventory_events/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "inventory_events_json_serde"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "event_id"
      type = "string"
    }

    columns {
      name = "event_timestamp"
      type = "string"
    }

    columns {
      name = "event_type"
      type = "string"
    }

    columns {
      name = "store_id"
      type = "string"
    }

    columns {
      name = "sku"
      type = "string"
    }

    columns {
      name = "inventory_remaining"
      type = "int"
    }

    columns {
      name = "threshold"
      type = "int"
    }

    columns {
      name = "processed_at"
      type = "string"
    }
  }
}

resource "aws_glue_catalog_table" "pricing_events" {
  name          = "pricing_events"
  database_name = aws_glue_catalog_database.retail_event_operations.name
  table_type    = "EXTERNAL_TABLE"

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.event_archive.bucket}/raw/pricing_events/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "pricing_events_json_serde"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "event_id"
      type = "string"
    }

    columns {
      name = "event_timestamp"
      type = "string"
    }

    columns {
      name = "event_type"
      type = "string"
    }

    columns {
      name = "store_id"
      type = "string"
    }

    columns {
      name = "fuel_grade"
      type = "string"
    }

    columns {
      name = "old_price"
      type = "double"
    }

    columns {
      name = "new_price"
      type = "double"
    }

    columns {
      name = "competitor_price"
      type = "double"
    }

    columns {
      name = "price_gap_vs_competitor"
      type = "double"
    }

    columns {
      name = "processed_at"
      type = "string"
    }
  }
}
resource "aws_cloudwatch_metric_alarm" "inventory_queue_depth_high" {
  alarm_name          = "${var.project}-${var.env}-inventory-queue-depth-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = 100
  alarm_description   = "Inventory SQS queue has more than 100 visible messages"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    QueueName = aws_sqs_queue.inventory_events.name
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "pricing_queue_depth_high" {
  alarm_name          = "${var.project}-${var.env}-pricing-queue-depth-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = 100
  alarm_description   = "Pricing SQS queue has more than 100 visible messages"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    QueueName = aws_sqs_queue.pricing_events.name
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "inventory_lambda_errors" {
  alarm_name          = "${var.project}-${var.env}-inventory-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Inventory Lambda has one or more errors"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.inventory_processor.function_name
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "pricing_lambda_errors" {
  alarm_name          = "${var.project}-${var.env}-pricing-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Pricing Lambda has one or more errors"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.pricing_processor.function_name
  }

  tags = local.tags
}
resource "aws_cloudwatch_dashboard" "retail_ops_dashboard" {
  dashboard_name = "${var.project}-${var.env}-operations-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.inventory_processor.function_name],
            [".", ".", ".", aws_lambda_function.pricing_processor.function_name]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Lambda Invocations"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.inventory_processor.function_name],
            [".", ".", ".", aws_lambda_function.pricing_processor.function_name]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Lambda Errors"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.inventory_events.name],
            [".", ".", ".", aws_sqs_queue.pricing_events.name],
            [".", ".", ".", aws_sqs_queue.inventory_events_dlq.name],
            [".", ".", ".", aws_sqs_queue.pricing_events_dlq.name]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "SQS Queue Depth"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.retail_operations.name],
            [".", "ConsumedWriteCapacityUnits", ".", aws_dynamodb_table.retail_operations.name]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "DynamoDB Capacity Usage"
        }
      }
    ]
  })
}