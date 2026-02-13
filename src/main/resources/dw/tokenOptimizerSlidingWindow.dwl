%dw 2.0
output application/json
var slideWindowMinutes = 10
var cutoffTime = now() - |PT10M|

var recentLogs = (payload.hits.hits default []) filter ((item) ->
    (item._source."@timestamp" as DateTime {format: "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"}) > cutoffTime
)

var groupedByMessage = (recentLogs map ((item) -> {
    timestamp: item._source."@timestamp",
    level: item._source.level,
    message: item._source.message,
    traceId: item._source.traceId default "N/A"
})) groupBy ((log) -> log.message)
    pluck ((logs, pattern) -> {
        occurrence_count: sizeOf(logs),
        first_seen: logs[0].timestamp,
        last_seen: logs[-1].timestamp,
        severity: logs[0].level,
        sample_message: pattern,
        trend: if (sizeOf(logs) > 5) "Escalating pattern" else "Isolated occurrences"
    })

---
{
    service: (payload.hits.hits[0]._source.service_name) if (sizeOf(payload.hits.hits default []) > 0) else "unknown",
    total_hits: payload.hits.total.value,
    analyzed_hits: sizeOf(recentLogs),
    time_window: "Last $(slideWindowMinutes) minutes",
    analysis_timestamp: now() as String {format: "yyyy-MM-dd'T'HH:mm:ss'Z'"},
    log_summary: (entriesOf(groupedByMessage) map $.value orderBy -$.occurrence_count)[0 to 10],
    context_summary: {
        most_common_severity: ((entriesOf(recentLogs groupBy $.level) orderBy -sizeOf($.value))[0].key) default "INFO",
        unique_trace_ids: sizeOf(recentLogs distinctBy $.traceId),
        recommendation: if (sizeOf(recentLogs filter ($.level == "ERROR")) > 20)
            "High error density detected - investigate immediately"
        else "Normal operational pattern"
    }
}
