%dw 2.0
output application/json
var severityThresholds = {
    critical: 90,
    high: 75,
    medium: 50
}

fun calculateSeverity(score: Number) =
    if (score >= severityThresholds.critical) "P1-Critical"
    else if (score >= severityThresholds.high) "P2-High"
    else if (score >= severityThresholds.medium) "P3-Medium"
    else "P4-Low"

var records = payload.records default []
var firstRecord = (records orderBy -$.record_score)[0]
---
{
    job_id: payload.job_id default "",
    analysis_timestamp: now(),
    total_anomalies: sizeOf(records),
    anomalies: records map ((record) -> {
        timestamp: record.timestamp,
        anomaly_score: record.record_score,
        severity: calculateSeverity(record.record_score),
        affected_service: record.by_field_value default "unknown",
        typical_value: record.typical[0] default 0,
        actual_value: record.actual[0] default 0,
        deviation_summary: "Observed value $(record.actual[0]) is $(round((record.actual[0] / record.typical[0]) * 100))% of typical baseline",
        recommended_action: if (record.record_score >= 90)
            "Immediate investigation required"
        else "Monitor for pattern escalation"
    }),
    highest_risk_service: if (firstRecord != null) firstRecord.by_field_value else "N/A"
}
