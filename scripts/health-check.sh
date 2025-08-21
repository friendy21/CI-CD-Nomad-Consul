#!/bin/bash

set -e

SERVICE_NAME=$1
SERVICE_PORT=$2
MAX_RETRIES=${3:-30}
RETRY_COUNT=0

if [ -z "$SERVICE_NAME" ] || [ -z "$SERVICE_PORT" ]; then
    echo "❌ Usage: $0 <service-name> <service-port> [max-retries]"
    exit 1
fi

echo "🔍 Checking health for $SERVICE_NAME on port $SERVICE_PORT..."

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -f -s http://localhost:$SERVICE_PORT/health > /dev/null; then
        echo "✅ $SERVICE_NAME is healthy!"
        
        # Get additional info
        HEALTH_INFO=$(curl -s http://localhost:$SERVICE_PORT/health | jq -r '.version // "unknown"' 2>/dev/null || echo "unknown")
        echo "📊 Service version: $HEALTH_INFO"
        
        exit 0
    fi
    
    echo "⏳ Attempt $((RETRY_COUNT + 1))/$MAX_RETRIES - Service not ready yet..."
    sleep 10
    RETRY_COUNT=$((RETRY_COUNT + 1))
done

echo "❌ $SERVICE_NAME failed health check after $MAX_RETRIES attempts"
exit 1
