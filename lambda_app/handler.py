"""
Generic AWS Lambda handler for simple Python apps.

Customize `lambda_handler` with your analysis logic.
Return JSON-serializable data. If used via Function URL, this returns JSON.
"""
import json
import os
from datetime import datetime


def lambda_handler(event, context):
    # Example analysis stub; replace with real logic.
    result = {
        "message": "hello from lambda",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "env": {"APP_ENV": os.getenv("APP_ENV", "dev")},
        "eventPreview": str(event)[:200],
    }

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(result),
    }

