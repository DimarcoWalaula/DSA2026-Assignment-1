import ballerina/time;

// ---------------------------------------------------------------------------
// Date arithmetic and identifier generation shared by the store and service.
//
// Dates cross the wire as ISO-8601 calendar dates ("YYYY-MM-DD"), which keeps
// JSON payloads human-readable. Internally each date is converted to an
// epoch-day integer so that "is this overdue", "do these ranges overlap" and
// "how many days late" all reduce to plain integer arithmetic.
// ---------------------------------------------------------------------------

const int SECONDS_PER_DAY = 86400;

// Converts an ISO-8601 calendar date to the number of whole days since the
// Unix epoch.
//
// + date - a date in `YYYY-MM-DD` form
// + return - the epoch-day number, or an error if `date` cannot be parsed
isolated function toEpochDay(string date) returns int|error {
    time:Utc utc = check time:utcFromString(date + "T00:00:00Z");
    return utc[0] / SECONDS_PER_DAY;
}

// `true` when `date` is a well-formed calendar date.
isolated function isValidDate(string date) returns boolean {
    int|error day = toEpochDay(date);
    return day is int;
}

// Whole days from `from` to `to` (negative if `to` is earlier than `from`).
isolated function daysBetween(string 'from, string to) returns int|error {
    int fromDay = check toEpochDay('from);
    int toDay = check toEpochDay(to);
    return toDay - fromDay;
}

// Today's date, in UTC, as `YYYY-MM-DD`.
isolated function today() returns string {
    time:Civil civil = time:utcToCivil(time:utcNow());
    return string `${civil.year}-${twoDigits(civil.month)}-${twoDigits(civil.day)}`;
}

isolated function twoDigits(int value) returns string {
    return value < 10 ? "0" + value.toString() : value.toString();
}

// `true` when `date` lies strictly before today.
isolated function isPast(string date) returns boolean {
    int|error elapsed = daysBetween(date, today());
    return elapsed is int && elapsed > 0;
}

// Half-open overlap test for two date ranges, `[startA, endA)` and
// `[startB, endB)`. A check-out on the day another booking checks in does not
// count as a clash.
isolated function rangesOverlap(string startA, string endA, string startB, string endB)
        returns boolean|error {
    int a1 = check toEpochDay(startA);
    int a2 = check toEpochDay(endA);
    int b1 = check toEpochDay(startB);
    int b2 = check toEpochDay(endB);
    return a1 < b2 && b1 < a2;
}

isolated int idSequence = 1000;

// Generates a short, readable, monotonically increasing identifier such as
// `LN-1001`.
isolated function nextId(string prefix) returns string {
    lock {
        idSequence += 1;
        return prefix + "-" + idSequence.toString();
    }
}
