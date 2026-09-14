import ballerina/time;

// ---------------------------------------------------------------------------
// Date arithmetic and identifier generation for the rental service.
// Calendar dates convert to epoch-day integers, which makes counting nights
// and detecting overlapping stays exact integer arithmetic rather than
// string comparison.
// ---------------------------------------------------------------------------

const int SECONDS_PER_DAY = 86400;

isolated function toEpochDay(string date) returns int|error {
    time:Utc utc = check time:utcFromString(date + "T00:00:00Z");
    return utc[0] / SECONDS_PER_DAY;
}

isolated function isValidDate(string date) returns boolean {
    int|error day = toEpochDay(date);
    return day is int;
}

// Number of nights between a check-in and a check-out date.
isolated function nightsBetween(string checkIn, string checkOut) returns int|error {
    int inDay = check toEpochDay(checkIn);
    int outDay = check toEpochDay(checkOut);
    return outDay - inDay;
}

// Half-open overlap test: a stay ending the day another begins does not clash.
isolated function staysOverlap(string firstIn, string firstOut, string secondIn, string secondOut)
        returns boolean|error {
    int a1 = check toEpochDay(firstIn);
    int a2 = check toEpochDay(firstOut);
    int b1 = check toEpochDay(secondIn);
    int b2 = check toEpochDay(secondOut);
    return a1 < b2 && b1 < a2;
}

isolated function today() returns string {
    time:Civil civil = time:utcToCivil(time:utcNow());
    return string `${civil.year}-${twoDigits(civil.month)}-${twoDigits(civil.day)}`;
}

isolated function twoDigits(int value) returns string {
    return value < 10 ? "0" + value.toString() : value.toString();
}

isolated int idSequence = 1000;

// Generates identifiers such as `PROP-1001` or `BKG-1042`.
isolated function nextId(string prefix) returns string {
    lock {
        idSequence += 1;
        return prefix + "-" + idSequence.toString();
    }
}

// Rounds a money amount to two decimal places so totals never carry a
// floating-point tail from a multiplication. `float` only has a
// zero-argument `round()` (nearest integer); routing through `decimal`,
// which supports a fraction-digit count, gets the two-decimal-place
// rounding this needs.
isolated function round2(float amount) returns float {
    decimal preciseAmount = <decimal>amount;
    return <float>preciseAmount.round(2);
}

isolated function equalsIgnoreCase(string a, string b) returns boolean {
    return a.toLowerAscii() == b.toLowerAscii();
}
