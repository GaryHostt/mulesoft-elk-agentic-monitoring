%dw 2.0
output application/json
fun convertISO8601ToES(duration: String): String =
    duration replace "PT" with ""
        replace "M" with "m"
        replace "H" with "h"
        replace "D" with "d"
---
{
    query: {
        bool: {
            must: [
                {
                    term: {
                        "service_name.keyword": payload.service_id
                    }
                }
            ],
            filter: [
                {
                    range: {
                        "@timestamp": {
                            gte: "now-" ++ convertISO8601ToES(payload.time_lookback default "PT15M"),
                            lte: "now",
                            format: "strict_date_optional_time"
                        }
                    }
                }
            ]
        }
    },
    size: 100,
    sort: [
        { "@timestamp": "desc" }
    ]
}
