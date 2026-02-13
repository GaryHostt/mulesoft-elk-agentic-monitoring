%dw 2.0
output application/json
var hits = payload.hits.hits default []
var totalValue = (payload.hits.total.value) if (payload.hits.total != null) otherwise 0
---
{
    service: (if (sizeOf(hits) > 0) hits[0]._source.service_name else "unknown"),
    total_hits: totalValue,
    time_window: "Lookback window applied",
    log_summary: (hits map ((item) -> {
        timestamp: item._source."@timestamp",
        level: item._source.level,
        message: item._source.message,
        traceId: item._source.traceId default "N/A"
    })) groupBy ((log) -> log.message)
        pluck ((logs, pattern) -> {
            occurrence_count: sizeOf(logs),
            last_seen: logs[-1].timestamp,
            severity: logs[0].level,
            sample_message: pattern
        })
}
