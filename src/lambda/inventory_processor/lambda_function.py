import json
import logging
import os
from datetime import datetime, timezone

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
s3 = boto3.client("s3")
sns = boto3.client("sns")

TABLE_NAME = os.environ["DYNAMODB_TABLE"]
BUCKET_NAME = os.environ["ARCHIVE_BUCKET"]
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]

table = dynamodb.Table(TABLE_NAME)


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def log_event(message, **kwargs):
    logger.info(json.dumps({"message": message, **kwargs}))


def archive_event(event_id, event_timestamp, item):
    s3_key = f"raw/inventory_events/{event_timestamp[:10]}/{event_id}.json"

    s3.put_object(
        Bucket=BUCKET_NAME,
        Key=s3_key,
        Body=json.dumps(item),
        ContentType="application/json",
    )

    return s3_key


def send_low_inventory_alert(item):
    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject="Low Inventory Alert",
        Message=json.dumps(item, indent=2),
    )


def process_record(record):
    body = json.loads(record["body"])
    detail = body.get("detail", {})

    event_id = detail.get("event_id")
    event_timestamp = detail.get("event_timestamp", utc_now())

    inventory_remaining = int(detail.get("inventory_remaining", 0))
    threshold = int(detail.get("threshold", 0))

    item = {
        "event_id": event_id,
        "event_timestamp": event_timestamp,
        "event_type": "inventory_event",
        "store_id": detail.get("store_id"),
        "sku": detail.get("sku"),
        "inventory_remaining": inventory_remaining,
        "threshold": threshold,
        "processed_at": utc_now(),
    }

    table.put_item(Item=item)

    s3_key = archive_event(event_id, event_timestamp, item)

    alert_sent = False
    if inventory_remaining < threshold:
        send_low_inventory_alert(item)
        alert_sent = True

    log_event(
        "inventory_event_processed",
        event_id=event_id,
        store_id=item["store_id"],
        sku=item["sku"],
        inventory_remaining=inventory_remaining,
        threshold=threshold,
        alert_sent=alert_sent,
        s3_key=s3_key,
        status="success",
    )


def lambda_handler(event, context):
    print("===== Inventory Processor Started =====")
    processed = 0

    for record in event.get("Records", []):
        try:
            process_record(record)
            processed += 1
        except Exception as error:
            log_event("inventory_event_failed", error=str(error), status="failed")
            raise

    print("Inventory event processed successfully.")

    return {
        "statusCode": 200,
        "processed_records": processed,
    }