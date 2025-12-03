#!/bin/bash
set -e

WORKFLOW_FILE=$1
WORKFLOW_NAME=$(grep "name:" "$WORKFLOW_FILE" | head -n 1 | awk '{print $2}')
NAMESPACE="tink-system"

if [ -z "$WORKFLOW_FILE" ]; then
    echo "Usage: $0 <workflow-yaml-file>"
    exit 1
fi

echo "🚀 Applying workflow $WORKFLOW_NAME from $WORKFLOW_FILE..."
kubectl apply -f "$WORKFLOW_FILE"

echo "⏳ Waiting for workflow to start..."
sleep 5

echo "👀 Monitoring workflow status..."
while true; do
    STATE=$(kubectl get workflow "$WORKFLOW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.state}')
    
    if [ "$STATE" == "SUCCESS" ]; then
        echo "✅ Workflow completed successfully!"
        break
    elif [ "$STATE" == "FAILED" ] || [ "$STATE" == "TIMEOUT" ]; then
        echo "❌ Workflow failed with state: $STATE"
        exit 1
    fi
    
    echo "   Current State: $STATE (checking again in 10s)..."
    sleep 10
done

echo "🧹 Cleaning up workflow..."
kubectl delete workflow "$WORKFLOW_NAME" -n "$NAMESPACE"

echo "🎉 Done! Machine should be rebooting into the new OS."
