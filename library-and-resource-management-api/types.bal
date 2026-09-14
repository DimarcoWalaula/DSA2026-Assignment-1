// ---------------------------------------------------------------------------
// DSA612S Assignment 1 - Question 1
// Distributed Library and Resource Management System
//
// Domain model. Every type is a closed (`record {| ... |}`) record so it maps
// cleanly onto JSON for HTTP payload binding and can be cloned safely across
// the data-store's lock boundary.
// ---------------------------------------------------------------------------

// Lifecycle state of a tracked resource (book, laptop, thin client, lab, room).
enum AssetStatus {
    AVAILABLE = "AVAILABLE",
    LOANED_OUT = "LOANED_OUT",
    OCCUPIED = "OCCUPIED",
    UNDER_MAINTENANCE = "UNDER_MAINTENANCE",
    DISPOSED = "DISPOSED"
}

// What kind of dated entry a `Schedule` represents.
enum ScheduleType {
    MAINTENANCE = "MAINTENANCE",
    SERVICING = "SERVICING",
    INSPECTION = "INSPECTION",
    BOOKING = "BOOKING"
}

// Lifecycle state of a work order raised against a faulty resource.
enum WorkOrderStatus {
    OPEN = "OPEN",
    IN_PROGRESS = "IN_PROGRESS",
    CLOSED = "CLOSED"
}

// A replaceable part of a complex asset, e.g. the stepper motor of a printer.
type Component record {|
    string compId;
    string name;
    string description = "";
|};

// A dated entry against an asset. For a `BOOKING` entry, `dueDate` is the
// check-in/start date and `endDate` the check-out/end date; for everything
// else `endDate` is left unset and `dueDate` is simply the date the work falls
// due.
type Schedule record {|
    string scheduleId;
    ScheduleType 'type;
    string dueDate;
    string? endDate = ();
    string? bookedBy = ();
    string description = "";
|};

// One unit of work inside a work order, e.g. "replace screen".
type Task record {|
    string taskId;
    string description;
    boolean completed = false;
|};

// A repair or servicing job raised against a faulty asset.
type WorkOrder record {|
    string orderId;
    WorkOrderStatus status = OPEN;
    string description;
    string openedDate = "";
    string? closedDate = ();
    Task[] tasks = [];
|};

// An active or historical loan of an asset to a borrower.
type Loan record {|
    string loanId;
    string borrower;
    string loanDate;
    string dueDate;
    string? returnedDate = ();
|};

// The aggregate root of the system. `assetTag` is the unique business key the
// data store is indexed on.
type Asset record {|
    string assetTag;
    string name;
    string description = "";
    string institution;
    string site;
    AssetStatus status = AVAILABLE;
    string dateAcquired;
    Component[] components = [];
    Schedule[] schedules = [];
    WorkOrder[] workOrders = [];
    Loan? currentLoan = ();
|};

// Partial-update payload for `PATCH /library/assets/{assetTag}`. Every field
// is optional; a field left out of the request body is left untouched.
type AssetPatch record {|
    string name?;
    string description?;
    string institution?;
    string site?;
    AssetStatus status?;
    string dateAcquired?;
|};

// A registered institution of higher learning, stored keyed on
// `institutionId` so the store can enforce uniqueness at the language level.
type Institution record {|
    readonly string institutionId;
    string name;
    string[] sites = [];
|};

// Payload for loaning an asset out to a borrower.
type LoanRequest record {|
    string borrower;
    string dueDate;
|};

// Payload for booking a lab or meeting room over a date range.
type BookingRequest record {|
    string bookedBy;
    string startDate;
    string endDate;
    string description = "";
|};

// Payload for changing a work order's status.
type WorkOrderUpdate record {|
    WorkOrderStatus status;
    string description?;
|};

// Uniform error body returned for every non-2xx response.
type ErrorResponse record {|
    string code;
    string message;
    string 'resource?;
|};

// One row of the maintenance/servicing overdue dashboard.
type OverdueEntry record {|
    string assetTag;
    string name;
    string institution;
    string site;
    AssetStatus status;
    string scheduleId;
    ScheduleType scheduleType;
    string dueDate;
    int daysOverdue;
    string description;
|};

// One row of the overdue-loans dashboard.
type OverdueLoan record {|
    string assetTag;
    string name;
    string institution;
    string borrower;
    string dueDate;
    int daysOverdue;
|};
