# ELK Agent System API

Mule 4 application implementing the ELK-Agent-System-API for unified log retrieval and MCP-hosted AI Agent tools, as specified in the Architecture Guide.

## Features

- **REST API** (APIKit): `GET /logs`, `GET /health`, `POST /mcp/tools/get_service_logs`, `POST /mcp/tools/check_anomaly_status`, `POST /mcp/tools/create_incident`
- **MCP tools**: `get_service_logs`, `check_anomaly_status`; Action Process API: `create_incident` (REST and MCP)
- **Elasticsearch** via HTTP connector (no deprecated ES connector)
- **DataWeave**: Query Engine (ISO8601 → ES DSL), Token Optimizer (optional sliding-window), PII redaction, Anomaly Score Parser
- **Validation**: `service_id` required before log search; `summary` and `severity` required for create_incident
- **Phase 2 Action Process API** (`src/main/mule/action-process-api.xml`): intelligent-incident-router (HITL when confidence &lt; 0.85), create-incident-flow (Jira + PagerDuty), Object Store idempotency and retry, error handling

## Configuration

Edit `src/main/resources/config.yaml` (or override via `config.yaml` in the app directory or Mule properties):

- `http.host`, `http.port` – listener (default `0.0.0.0`, `8081`)
- `elasticsearch.host`, `elasticsearch.port`, `elasticsearch.protocol`, `elasticsearch.index`, `elasticsearch.requestTimeout`, `elasticsearch.useSlidingWindow`
- `mcp.endpointPath` – MCP endpoint path (default `/mcp`)
- **Phase 2**: `jira.host`, `jira.username`, `jira.apiToken`; `pagerduty.routingKey`; `slack.webhookPath`

## Action Process API

The Action Process API (Layer 2) is implemented in [src/main/mule/action-process-api.xml](src/main/mule/action-process-api.xml) and imported from the main app ([elk-mcp-project.xml](src/main/mule/elk-mcp-project.xml)).

- **Entry point:** REST `POST /mcp/tools/create_incident` (defined in [api.raml](src/main/api/api.raml)). The flow `create-incident-entry` validates `summary` and `severity`, then calls `intelligent-incident-router`.
- **Flows:**
  - **create-incident-entry:** Validates input, flow-refs the router, and handles validation and generic errors.
  - **intelligent-incident-router:** If `confidence_score` is present and &lt; 0.85, the incident is stored in Object Store (pending HITL), Slack is notified (HITL), and the response is `pending_review`; otherwise it flow-refs **create-incident-flow**.
  - **create-incident-flow:** Idempotency is enforced by key (`anomaly_id` or hash of `summary`) using **Incident_Idempotency_Object_Store**. If already processed, the stored result is returned. Otherwise: P1-Critical incidents trigger a Scatter-Gather to **create-jira-issue-flow** and **create-pagerduty-event-flow**; other severities use Jira only. Results are combined and stored for idempotency. The flow is wrapped in try/error-handler (HTTP or connector failures produce an error payload and optionally store for retry in **Pending_Incidents_Object_Store**).
  - **create-jira-issue-flow:** Builds the Jira issue body, POSTs to the Jira REST API (Basic auth from config), and returns `{ severity, jira: { key, id } }`.
  - **create-pagerduty-event-flow:** Builds the PagerDuty Events v2 body, POSTs to PagerDuty, and returns `{ severity, pagerduty: { dedup_key } }`.
- **Object Stores:** **Pending_Incidents_Object_Store** (HITL and retry, 7 days TTL), **Incident_Idempotency_Object_Store** (24h TTL).
- **Configuration:** `jira.host`, `jira.username`, `jira.apiToken`; `pagerduty.routingKey`; `slack.webhookPath`. HTTP configs for Jira, PagerDuty, and Slack are in [global.xml](src/main/mule/global.xml).

## Dependencies

The project uses:

- **HTTP Connector** (org.mule.connectors:mule-http-connector)
- **MCP Connector** (com.mulesoft.connectors:mule-mcp-connector)
- **APIKit** (org.mule.modules:mule-apikit-module)
- **Validation Module** (org.mule.modules:mule-validation-module)
- **Phase 2**: Object Store (org.mule.connectors:mule-objectstore-connector), Jira (com.mulesoft.connectors:mule4-jira-connector), Slack (com.mulesoft.connectors:mule4-slack-connector); PagerDuty via HTTP

These are resolved from Anypoint Exchange and Mulesoft repositories. If `mvn compile` fails to resolve them, configure Maven with your Anypoint credentials (e.g. in `~/.m2/settings.xml`) for the Exchange repository.

## Build and run

```bash
mvn clean package
# Run locally (e.g. with Mule runtime or Anypoint Studio)
```

- **API console:** With the app running, open **http://localhost:8081/console** (or `http://<host>:<port>/console` if you change `http.port` or host) to browse and try the API. The console is enabled by default with APIKit.

## Validating connection to local ELK

The app is configured for a local Elasticsearch at `localhost:9200` and index `my-index` (see `src/main/resources/config.yaml`). To validate connectivity and operations:

1. **Start your local ELK stack** (Elasticsearch on port 9200).
2. **Start the Mule app** (e.g. from Anypoint Studio or your Mule runtime).
3. Run the validation script:

   ```bash
   ./scripts/validate-local-elk.sh
   ```

   Optional: `./scripts/validate-local-elk.sh [ES_HOST] [ES_PORT] [MULE_BASE_URL]` to override defaults.

- **If Elasticsearch is unreachable:** Fix the ELK stack (start ES, open port, or set `elasticsearch.host`/`port` in config).
- **If GET /logs returns 502 or empty:** Ensure the index exists and documents have `service_name` (keyword), `@timestamp`, `level`, `message`. Otherwise create the index or align field names (see plan “Who to change”).
- **If check_anomaly_status fails (ML):** Enable X-Pack ML and create an anomaly detection job in Elasticsearch, or omit this operation.

## API usage

- **GET /logs?service_id=my-service&time_lookback=PT5M** – token-optimized, PII-redacted log summary; optional `use_sliding_window=true`
- **GET /health** – liveness
- **POST /mcp/tools/get_service_logs** – body: `{"service_id":"...","time_lookback":"PT5M","use_sliding_window":false}`
- **POST /mcp/tools/check_anomaly_status** – body: `{"job_id":"..."}`
- **POST /mcp/tools/create_incident** – body: `{"severity":"P1-Critical","summary":"...","anomaly_id":"...","reasoning":"...","confidence_score":0.9}`; when `confidence_score` &lt; 0.85, incident is queued for HITL (Slack); else Jira and/or PagerDuty are called with idempotency and error handling.

MCP tools are also callable by AI agents via the MCP endpoint configured in `global.xml`.
