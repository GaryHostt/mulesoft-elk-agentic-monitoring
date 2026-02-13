%dw 2.0
output application/json
fun redactSSN(text: String): String =
    text replace /\b\d{3}-\d{2}-\d{4}\b/ with "***-**-****"

fun redactEmail(text: String): String =
    text replace /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/ with "[EMAIL_REDACTED]"

fun redactCreditCard(text: String): String =
    text replace /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/ with "****-****-****-****"

fun redactPhone(text: String): String =
    text replace /\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/ with "***-***-****"

fun redactIPv4(text: String): String =
    text replace /\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/ with "[IP_REDACTED]"

fun sanitizeText(text: String): String =
    text
        |> redactSSN($)
        |> redactEmail($)
        |> redactCreditCard($)
        |> redactPhone($)
        |> redactIPv4($)

---
{
    service: payload.service,
    total_hits: payload.total_hits,
    time_window: payload.time_window,
    log_summary: payload.log_summary map ((logGroup) -> {
        occurrence_count: logGroup.occurrence_count,
        last_seen: logGroup.last_seen,
        severity: logGroup.severity,
        sample_message: sanitizeText(logGroup.sample_message as String),
        pii_redacted: true
    }),
    compliance_notice: "PII redacted per GDPR/CCPA requirements"
}
