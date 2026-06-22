import json
import random
import uuid
from datetime import datetime, timezone
import boto3

EVENT_BUS_NAME = "event-driven-retail-operations-pipeline-dev-bus"
SOURCE = "retail.operations"
REGION = "us-east-1"

eventbridge = boto3.client("events", region_name=REGION)

stores = ["store_1", "store_2", "store_3"]
skus = ["COKE-12OZ", "CHIPS-LAYS", "WATER-1L", "BEER-CAN", "MOTOR-OIL"]
fuel_grades = ["Regular", "Midgrade", "Premium", "Diesel"]


def current_timestamp():
    return datetime.now(timezone.utc).isoformat()


def generate_inventory_event():
    threshold = random.choice([15, 20, 25])
    inventory_remaining = random.randint(0, 50)

    return {
        "event_id": f"inv-{uuid.uuid4()}",
        "event_type": "inventory_event",
        "store_id": random.choice(stores),
        "sku": random.choice(skus),
        "inventory_remaining": inventory_remaining,
        "threshold": threshold,
        "event_timestamp": current_timestamp(),
    }


def generate_pricing_event():
    old_price = round(random.uniform(2.80, 4.20), 2)
    price_change = round(random.uniform(-0.10, 0.15), 2)
    new_price = round(old_price + price_change, 2)
    competitor_price = round(new_price + random.uniform(-0.08, 0.08), 2)

    return {
        "event_id": f"price-{uuid.uuid4()}",
        "event_type": "pricing_event",
        "store_id": random.choice(stores),
        "fuel_grade": random.choice(fuel_grades),
        "old_price": old_price,
        "new_price": new_price,
        "competitor_price": competitor_price,
        "event_timestamp": current_timestamp(),
    }


def publish_event(event):
    detail_type = event["event_type"]

    response = eventbridge.put_events(
        Entries=[
            {
                "Source": SOURCE,
                "DetailType": detail_type,
                "EventBusName": EVENT_BUS_NAME,
                "Detail": json.dumps(event),
            }
        ]
    )

    return response


def main(total_events=20):
    success_count = 0
    failed_count = 0

    for _ in range(total_events):
        event = random.choice([
            generate_inventory_event(),
            generate_pricing_event(),
        ])

        response = publish_event(event)

        if response["FailedEntryCount"] == 0:
            success_count += 1
            print(f"Published: {event['event_type']} | {event['event_id']}")
        else:
            failed_count += 1
            print(f"Failed: {event['event_id']} | {response}")

    print("\nEvent publishing completed.")
    print(f"Successful events: {success_count}")
    print(f"Failed events: {failed_count}")


if __name__ == "__main__":
    main(total_events=20)
