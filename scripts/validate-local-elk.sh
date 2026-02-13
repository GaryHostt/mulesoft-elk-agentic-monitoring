#!/usr/bin/env bash
# Validate Mule app connection to local ELK stack (plan: connect_mule_app_to_local_elk).
# Usage: ./scripts/validate-local-elk.sh [ES_HOST] [ES_PORT] [MULE_BASE_URL]
# Defaults: ES localhost:9200, Mule http://localhost:8081

ES_HOST="${1:-localhost}"
ES_PORT="${2:-9200}"
MULE_BASE="${3:-http://localhost:8081}"
CONNECT_TIMEOUT=3

echo "=== 1. Elasticsearch connectivity ==="
if curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$CONNECT_TIMEOUT" "http://${ES_HOST}:${ES_PORT}/" | grep -q '200'; then
  echo "OK: Elasticsearch at ${ES_HOST}:${ES_PORT} is reachable."
  curl -s "http://${ES_HOST}:${ES_PORT}/_cluster/health?pretty" 2>/dev/null | head -20 || true
else
  echo "FAIL: Cannot reach Elasticsearch at ${ES_HOST}:${ES_PORT}. Fix ELK stack: ensure ES is running and port is open."
  echo "  (Connection refused or timeout = start Elasticsearch or check host/port in config.yaml)"
fi

echo ""
echo "=== 2. Mule app health (no ES dependency) ==="
HEALTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$CONNECT_TIMEOUT" "${MULE_BASE}/health" 2>/dev/null || echo "000")
if [ "$HEALTH_CODE" = "200" ]; then
  echo "OK: GET /health returned 200."
  curl -s "${MULE_BASE}/health"
  echo ""
else
  echo "FAIL: GET /health returned ${HEALTH_CODE}. Start the Mule app (e.g. run from Anypoint Studio or Mule runtime), then re-run this script."
fi

echo ""
echo "=== 3. Log search (GET /logs) ==="
# RAML may require client_id/client_secret; try without first
LOGS_CODE=$(curl -s -o /tmp/validate-logs.json -w "%{http_code}" --connect-timeout "$CONNECT_TIMEOUT" "${MULE_BASE}/logs?service_id=test-service&time_lookback=PT15M" 2>/dev/null || echo "000")
if [ "$LOGS_CODE" = "200" ]; then
  echo "OK: GET /logs returned 200."
  head -c 500 /tmp/validate-logs.json
  echo ""
  if grep -q '"error"' /tmp/validate-logs.json 2>/dev/null; then
    echo "  Note: Response contains error (e.g. Elasticsearch unavailable or index missing). Check ELK stack and index name in config.yaml."
  fi
elif [ "$LOGS_CODE" = "502" ]; then
  echo "FAIL: GET /logs returned 502. Usually Elasticsearch unavailable or index missing. Fix ELK stack (ensure ES running and index exists with service_name, @timestamp)."
  cat /tmp/validate-logs.json 2>/dev/null; echo ""
else
  echo "Result: GET /logs returned ${LOGS_CODE}. Ensure Mule app is running and optionally pass client_id/client_secret if required."
  cat /tmp/validate-logs.json 2>/dev/null; echo ""
fi

echo ""
echo "=== 4. Anomaly status (POST /mcp/tools/check_anomaly_status) ==="
ANOM_CODE=$(curl -s -o /tmp/validate-anom.json -w "%{http_code}" -X POST --connect-timeout "$CONNECT_TIMEOUT" -H "Content-Type: application/json" -d '{"job_id":"test-job"}' "${MULE_BASE}/mcp/tools/check_anomaly_status" 2>/dev/null || echo "000")
if [ "$ANOM_CODE" = "200" ]; then
  echo "OK: POST check_anomaly_status returned 200."
  cat /tmp/validate-anom.json
  echo ""
  if grep -q '"error"' /tmp/validate-anom.json 2>/dev/null; then
    echo "  Note: Response may indicate ML not available or job missing. Enable X-Pack ML and create a job, or ignore if not using anomaly detection."
  fi
elif [ "$ANOM_CODE" = "502" ]; then
  echo "FAIL or N/A: POST check_anomaly_status returned 502. If ML is not enabled or job does not exist, fix ELK stack (enable X-Pack ML, create job)."
  cat /tmp/validate-anom.json 2>/dev/null; echo ""
else
  echo "Result: POST check_anomaly_status returned ${ANOM_CODE}. Ensure Mule app is running."
  cat /tmp/validate-anom.json 2>/dev/null; echo ""
fi

echo ""
echo "=== Summary ==="
echo "If ES is unreachable: fix ELK stack (start Elasticsearch)."
echo "If Mule /health fails: start the Mule app."
echo "If /logs returns 502 or error: check ES and index (config.yaml elasticsearch.index; index must have service_name, @timestamp, level, message)."
echo "If check_anomaly_status fails with ML error: enable ML (X-Pack) and create a job in ELK, or omit this operation."
