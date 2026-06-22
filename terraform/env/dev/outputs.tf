output "event_archive_bucket" {
  value = aws_s3_bucket.event_archive.bucket
}

output "event_bus_name" {
  value = aws_cloudwatch_event_bus.retail_ops.name
}

output "inventory_queue_url" {
  value = aws_sqs_queue.inventory_events.url
}

output "pricing_queue_url" {
  value = aws_sqs_queue.pricing_events.url
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.retail_operations.name
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}
output "glue_database_name" {
  value = aws_glue_catalog_database.retail_event_operations.name
}

output "athena_results_path" {
  value = "s3://${aws_s3_bucket.event_archive.bucket}/athena-results/"
}
output "inventory_dlq_url" {
  value = aws_sqs_queue.inventory_events_dlq.url
}

output "pricing_dlq_url" {
  value = aws_sqs_queue.pricing_events_dlq.url
}
output "cloudwatch_dashboard_name" {
  value = aws_cloudwatch_dashboard.retail_ops_dashboard.dashboard_name
}