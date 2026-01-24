#!/bin/bash
#
# Manually trigger a sync job
#
# Usage:
#   sync-now.sh [gitlab|jira|sonarqube|all]
#
set -e

JOB="${1:-all}"
GATEWAY_URL="http://localhost:${GATEWAY_PORT:-8080}"

case "$JOB" in
    gitlab)
        echo "Triggering GitLab sync..."
        curl -s -X POST "$GATEWAY_URL/api/jobs/gitlab" | jq .
        ;;
    jira)
        echo "Triggering Jira sync..."
        curl -s -X POST "$GATEWAY_URL/api/jobs/jira" | jq .
        ;;
    sonarqube)
        echo "Triggering SonarQube sync..."
        curl -s -X POST "$GATEWAY_URL/api/jobs/sonarqube" | jq .
        ;;
    all)
        echo "Triggering all syncs..."
        curl -s -X POST "$GATEWAY_URL/api/jobs/gitlab" | jq .
        curl -s -X POST "$GATEWAY_URL/api/jobs/jira" | jq .
        curl -s -X POST "$GATEWAY_URL/api/jobs/sonarqube" | jq .
        ;;
    status)
        echo "Sync status:"
        curl -s "$GATEWAY_URL/actuator/health" | jq .
        ;;
    *)
        echo "Usage: sync-now.sh [gitlab|jira|sonarqube|all|status]"
        exit 1
        ;;
esac
