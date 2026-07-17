import base64
import json

def lambda_handler(event, context):
    print(f"Processing batch of {len(event['Records'])} records...")
    
    for record in event['Records']:
        try:
            # Decode the payload written by API Gateway
            payload = base64.b64decode(record['kinesis']['data']).decode('utf-8')
            event_data = json.loads(payload)
            print(f"Successfully processed event: {event_data.get('eventType', 'unknown')} for user {event_data.get('userId', 'unknown')}")
        except Exception as e:
            print(f"Error processing record: {e}")
            # Raise exception to trigger the DLQ retry policy
            raise e
            
    return {"statusCode": 200, "body": "Processed"}
