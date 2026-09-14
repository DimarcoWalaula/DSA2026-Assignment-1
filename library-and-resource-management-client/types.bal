// ---------------------------------------------------------------------------
// Client-side view of the API contract.
//
// This is a separate Ballerina package with its own copy of the resource
// representations: the client knows the service only through its published
// JSON contract, which is exactly the loose coupling a distributed system is
// meant to have between independent processes.
// ---------------------------------------------------------------------------

enum AssetStatus {
    AVAILABLE = "AVAILABLE",
    LOANED_OUT = "LOANED_OUT",
    OCCUPIED = "OCCUPIED",
    UNDER_MAINTENANCE = "UNDER_MAINTENANCE",
    DISPOSED = "DISPOSED"
}

enum ScheduleType {
    MAINTENANCE = "MAINTENANCE",
    SERVICING = "SERVICING",
    INSPECTION = "INSPECTION",
    BOOKING = "BOOKING"
}

enum WorkOrderStatus {
    OPEN = "OPEN",
    IN_PROGRESS = "IN_PROGRESS",
    CLOSED = "CLOSED"
}

type Component record {|
    string compId;
    string name;
    string description = "";
|};

type Schedule record {|
    string scheduleId;
    ScheduleType 'type;
    string dueDate;
    string description = "";
    string? endDate = ();
    string? bookedBy = ();
|};

type Task record {|
    string taskId;
    string description;
    boolean completed = false;
|};

type WorkOrder record {|
    string orderId;
    WorkOrderStatus status = OPEN;
    string description;
    string openedDate = "";
    string? closedDate = ();
    Task[] tasks = [];
|};

type Loan record {|
    string loanId;
    string borrower;
    string loanDate;
    string dueDate;
    string? returnedDate = ();
|};

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

type Institution record {|
    string institutionId;
    string name;
    string[] sites = [];
|};

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

type OverdueLoan record {|
    string assetTag;
    string name;
    string institution;
    string borrower;
    string dueDate;
    int daysOverdue;
|};
