// ---------------------------------------------------------------------------
// In-memory data layer for the library and resource management system.
//
// Assets live in a `map<Asset>` keyed on the unique `assetTag`, which gives
// O(1) lookup, insert and delete on the natural business key required by the
// brief. Institutions live in a `table<Institution> key(institutionId)`,
// which enforces key uniqueness at the language level rather than by hand.
//
// Both module-level variables are declared `isolated`; every access happens
// inside a `lock` block so the store stays correct while the HTTP listener
// serves requests concurrently. Values are `clone()`d on the way in and out
// of the lock so no caller can mutate stored state by holding a reference to
// it.
// ---------------------------------------------------------------------------

// Raised when the requested entity does not exist.
type NotFoundError distinct error;

// Raised when an entity with the same unique key already exists, or an
// operation would leave the store in an inconsistent state.
type ConflictError distinct error;

// Raised when a payload is syntactically valid JSON but semantically wrong.
type ValidationError distinct error;

isolated map<Asset> assetsByTag = {};
isolated table<Institution> key(institutionId) institutions = table [];

// ------------------------------ institutions --------------------------------

isolated function listInstitutions() returns Institution[] {
    lock {
        return institutions.toArray().clone();
    }
}

isolated function getInstitution(string institutionId) returns Institution|NotFoundError {
    lock {
        Institution? found = institutions[institutionId];
        if found is () {
            return error NotFoundError("No institution registered with id '" + institutionId + "'");
        }
        return found.clone();
    }
}

isolated function addInstitution(Institution institution) returns Institution|ConflictError|ValidationError {
    if institution.institutionId.trim() == "" || institution.name.trim() == "" {
        return error ValidationError("'institutionId' and 'name' are required");
    }
    lock {
        if institutions.hasKey(institution.institutionId) {
            return error ConflictError("Institution '" + institution.institutionId + "' is already registered");
        }
        institutions.add(institution.clone());
        return institution.clone();
    }
}

// Adds a site/campus to an existing institution.
isolated function addSite(string institutionId, string site) returns Institution|NotFoundError|ConflictError|ValidationError {
    if site.trim() == "" {
        return error ValidationError("'site' is required");
    }
    lock {
        Institution? found = institutions[institutionId];
        if found is () {
            return error NotFoundError("No institution registered with id '" + institutionId + "'");
        }
        if found.sites.indexOf(site) != () {
            return error ConflictError("Site '" + site + "' is already listed for this institution");
        }
        found.sites.push(site);
        return found.clone();
    }
}

// Removes an institution from the Ministry listing. Refused while it still
// owns registered assets, so the catalogue never points at an institution
// that no longer exists.
isolated function removeInstitution(string institutionId) returns Institution|NotFoundError|ConflictError {
    Institution target = check getInstitution(institutionId);
    lock {
        foreach Asset asset in assetsByTag {
            if asset.institution == target.name {
                return error ConflictError("Institution '" + target.name
                        + "' still has assets registered against it; remove or reassign them first");
            }
        }
    }
    lock {
        Institution removed = institutions.remove(institutionId);
        return removed.clone();
    }
}

isolated function institutionIsRegistered(string name) returns boolean {
    lock {
        foreach Institution institution in institutions {
            if institution.name == name {
                return true;
            }
        }
        return false;
    }
}

// --------------------------------- assets -----------------------------------

isolated function listAssets() returns Asset[] {
    lock {
        return assetsByTag.toArray().clone();
    }
}

isolated function getAsset(string assetTag) returns Asset|NotFoundError {
    lock {
        Asset? found = assetsByTag[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        return found.clone();
    }
}

isolated function equalsIgnoreCase(string a, string b) returns boolean {
    return a.toLowerAscii() == b.toLowerAscii();
}

// Filters the catalogue by institution, site and/or status. Any argument left
// as `()` is ignored, so this single function backs the global view, the
// campus view and the status view alike.
isolated function filterAssets(string? institution, string? site, AssetStatus? status) returns Asset[] {
    lock {
        Asset[] matches = [];
        foreach Asset asset in assetsByTag {
            if institution is string && !equalsIgnoreCase(asset.institution, institution) {
                continue;
            }
            if site is string && !equalsIgnoreCase(asset.site, site) {
                continue;
            }
            if status is AssetStatus && asset.status != status {
                continue;
            }
            matches.push(asset);
        }
        return matches.clone();
    }
}

isolated function validateAsset(Asset asset) returns ValidationError? {
    if asset.assetTag.trim() == "" {
        return error ValidationError("'assetTag' must not be empty");
    }
    if asset.name.trim() == "" {
        return error ValidationError("'name' must not be empty");
    }
    if !isValidDate(asset.dateAcquired) {
        return error ValidationError("'dateAcquired' must be a calendar date in YYYY-MM-DD form");
    }
    if !institutionIsRegistered(asset.institution) {
        return error ValidationError("'" + asset.institution
                + "' is not a registered institution; register it via POST /library/institutions first");
    }
    foreach Schedule schedule in asset.schedules {
        if !isValidDate(schedule.dueDate) {
            return error ValidationError("Schedule '" + schedule.scheduleId
                    + "' has an invalid dueDate '" + schedule.dueDate + "'");
        }
    }
    return ();
}

isolated function addAsset(Asset asset) returns Asset|ConflictError|ValidationError {
    ValidationError? invalid = validateAsset(asset);
    if invalid is ValidationError {
        return invalid;
    }
    lock {
        if assetsByTag.hasKey(asset.assetTag) {
            return error ConflictError("An asset with tag '" + asset.assetTag + "' already exists");
        }
        assetsByTag[asset.assetTag] = asset.clone();
        return asset.clone();
    }
}

// Full replacement (idempotent `PUT`). The tag in the URL path always wins
// over any tag in the payload, so the unique key can never be changed by an
// update.
isolated function replaceAsset(string assetTag, Asset asset) returns Asset|NotFoundError|ValidationError {
    Asset replacement = asset.clone();
    replacement.assetTag = assetTag;
    ValidationError? invalid = validateAsset(replacement);
    if invalid is ValidationError {
        return invalid;
    }
    lock {
        if !assetsByTag.hasKey(assetTag) {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        assetsByTag[assetTag] = replacement.clone();
        return replacement.clone();
    }
}

// Partial update (`PATCH`). Only fields present in `patch` are applied.
isolated function patchAsset(string assetTag, AssetPatch patch) returns Asset|NotFoundError|ValidationError {
    string? newDate = patch?.dateAcquired;
    if newDate is string && !isValidDate(newDate) {
        return error ValidationError("'dateAcquired' must be a calendar date in YYYY-MM-DD form");
    }
    string? newInstitution = patch?.institution;
    if newInstitution is string && !institutionIsRegistered(newInstitution) {
        return error ValidationError("'" + newInstitution + "' is not a registered institution");
    }
    lock {
        Asset? found = assetsByTag[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        AssetPatch changes = patch.clone();
        string? name = changes?.name;
        if name is string {
            found.name = name;
        }
        string? description = changes?.description;
        if description is string {
            found.description = description;
        }
        string? institution = changes?.institution;
        if institution is string {
            found.institution = institution;
        }
        string? site = changes?.site;
        if site is string {
            found.site = site;
        }
        AssetStatus? status = changes?.status;
        if status is AssetStatus {
            found.status = status;
        }
        string? dateAcquired = changes?.dateAcquired;
        if dateAcquired is string {
            found.dateAcquired = dateAcquired;
        }
        return found.clone();
    }
}

isolated function deleteAsset(string assetTag) returns Asset|NotFoundError {
    lock {
        Asset? removed = assetsByTag.removeIfHasKey(assetTag);
        if removed is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        return removed.clone();
    }
}

// ------------------------------- components ---------------------------------

isolated function addComponent(string assetTag, Component component)
        returns Asset|NotFoundError|ConflictError|ValidationError {
    if component.compId.trim() == "" || component.name.trim() == "" {
        return error ValidationError("'compId' and 'name' are required for a component");
    }
    lock {
        Asset? found = assetsByTag[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        foreach Component existing in found.components {
            if existing.compId == component.compId {
                return error ConflictError("Component '" + component.compId
                        + "' is already attached to asset '" + assetTag + "'");
            }
        }
        found.components.push(component.clone());
        return found.clone();
    }
}

isolated function removeComponent(string assetTag, string compId) returns Asset|NotFoundError {
    lock {
        Asset? found = assetsByTag[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        Component[] remaining = from Component component in found.components
            where component.compId != compId
            select component;
        if remaining.length() == found.components.length() {
            return error NotFoundError("Asset '" + assetTag + "' has no component '" + compId + "'");
        }
        found.components = remaining;
        return found.clone();
    }
}

// -------------------------------- schedules ----------------------------------

isolated function hasActiveBooking(Asset asset) returns boolean {
    foreach Schedule schedule in asset.schedules {
        if schedule.'type != BOOKING {
            continue;
        }
        string endDate = schedule.endDate ?: schedule.dueDate;
        if !isPast(endDate) {
            return true;
        }
    }
    return false;
}

isolated function addSchedule(string assetTag, Schedule schedule)
        returns Asset|NotFoundError|ConflictError|ValidationError {
    if schedule.scheduleId.trim() == "" {
        return error ValidationError("'scheduleId' is required for a schedule");
    }
    if !isValidDate(schedule.dueDate) {
        return error ValidationError("'dueDate' must be a calendar date in YYYY-MM-DD form");
    }
    lock {
        Asset? found = assetsByTag[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        foreach Schedule existing in found.schedules {
            if existing.scheduleId == schedule.scheduleId {
                return error ConflictError("Schedule '" + schedule.scheduleId
                        + "' already exists on asset '" + assetTag + "'");
            }
        }
        found.schedules.push(schedule.clone());
        return found.clone();
    }
}

isolated function removeSchedule(string assetTag, string scheduleId) returns Asset|NotFoundError {
    lock {
        Asset? found = assetsByTag[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        Schedule[] remaining = from Schedule schedule in found.schedules
            where schedule.scheduleId != scheduleId
            select schedule;
        if remaining.length() == found.schedules.length() {
            return error NotFoundError("Asset '" + assetTag + "' has no schedule '" + scheduleId + "'");
        }
        found.schedules = remaining;
        if found.status == OCCUPIED && !hasActiveBooking(found) {
            found.status = AVAILABLE;
        }
        return found.clone();
    }
}

// Books a lab or meeting room for a date range. The booking is stored as a
// `BOOKING`-typed schedule so a single collection carries both servicing and
// occupancy information for a resource.
isolated function bookAsset(string assetTag, BookingRequest request)
        returns Asset|NotFoundError|ConflictError|ValidationError {
    if request.bookedBy.trim() == "" {
        return error ValidationError("'bookedBy' is required");
    }
    if !isValidDate(request.startDate) || !isValidDate(request.endDate) {
        return error ValidationError("'startDate' and 'endDate' must be calendar dates in YYYY-MM-DD form");
    }
    int|error span = daysBetween(request.startDate, request.endDate);
    if span is error || span <= 0 {
        return error ValidationError("'endDate' must be after 'startDate'");
    }
    string scheduleId = nextId("BKG");
    lock {
        Asset? found = assetsByTag[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        if found.status == UNDER_MAINTENANCE || found.status == DISPOSED {
            return error ConflictError("Asset '" + assetTag + "' is " + found.status + " and cannot be booked");
        }
        foreach Schedule schedule in found.schedules {
            if schedule.'type != BOOKING {
                continue;
            }
            string otherEnd = schedule.endDate ?: schedule.dueDate;
            boolean|error clash = rangesOverlap(request.startDate, request.endDate, schedule.dueDate, otherEnd);
            if clash is boolean && clash {
                return error ConflictError("Asset '" + assetTag + "' is already booked from "
                        + schedule.dueDate + " to " + otherEnd);
            }
        }
        found.schedules.push({
            scheduleId: scheduleId,
            'type: BOOKING,
            dueDate: request.startDate,
            endDate: request.endDate,
            bookedBy: request.bookedBy,
            description: request.description
        });
        found.status = OCCUPIED;
        return found.clone();
    }
}

// ------------------------------- work orders ---------------------------------

isolated function hasOpenWorkOrder(Asset asset) returns boolean {
    foreach WorkOrder workOrder in asset.workOrders {
        if workOrder.status != CLOSED {
            return true;
        }
    }
    return false;
}

isolated function addWorkOrder(string assetTag, WorkOrder workOrder)
        returns Asset|NotFoundError|ConflictError|ValidationError {
    if workOrder.description.trim() == "" {
        return error ValidationError("'description' is required for a work order");
    }
    string generatedId = nextId("WO");
    lock {
        Asset? found = assetsByTag[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        WorkOrder candidate = workOrder.clone();
        if candidate.orderId.trim() == "" {
            candidate.orderId = generatedId;
        }
        foreach WorkOrder existing in found.workOrders {
            if existing.orderId == candidate.orderId {
                return error ConflictError("Work order '" + candidate.orderId
                        + "' already exists on asset '" + assetTag + "'");
            }
        }
        if candidate.openedDate == "" {
            candidate.openedDate = today();
        }
        found.workOrders.push(candidate);
        found.status = UNDER_MAINTENANCE;
        return found.clone();
    }
}

isolated function updateWorkOrder(string assetTag, string orderId, WorkOrderUpdate update)
        returns Asset|NotFoundError {
    lock {
        Asset? found = assetsByTag[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        boolean matched = false;
        foreach WorkOrder workOrder in found.workOrders {
            if workOrder.orderId != orderId {
                continue;
            }
            matched = true;
            workOrder.status = update.status;
            string? description = update?.description;
            if description is string {
                workOrder.description = description;
            }
            if update.status == CLOSED {
                workOrder.closedDate = today();
            }
        }
        if !matched {
            return error NotFoundError("Asset '" + assetTag + "' has no work order '" + orderId + "'");
        }
        if found.status == UNDER_MAINTENANCE && !hasOpenWorkOrder(found) {
            found.status = AVAILABLE;
        }
        return found.clone();
    }
}

isolated function addTask(string assetTag, string orderId, Task task)
        returns Asset|NotFoundError|ConflictError|ValidationError {
    if task.description.trim() == "" {
        return error ValidationError("'description' is required for a task");
    }
    string generatedId = nextId("T");
    lock {
        Asset? found = assetsByTag[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        foreach WorkOrder workOrder in found.workOrders {
            if workOrder.orderId != orderId {
                continue;
            }
            Task candidate = task.clone();
            if candidate.taskId.trim() == "" {
                candidate.taskId = generatedId;
            }
            foreach Task existing in workOrder.tasks {
                if existing.taskId == candidate.taskId {
                    return error ConflictError("Task '" + candidate.taskId
                            + "' already exists on work order '" + orderId + "'");
                }
            }
            workOrder.tasks.push(candidate);
            return found.clone();
        }
        return error NotFoundError("Asset '" + assetTag + "' has no work order '" + orderId + "'");
    }
}

isolated function removeTask(string assetTag, string orderId, string taskId) returns Asset|NotFoundError {
    lock {
        Asset? found = assetsByTag[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        foreach WorkOrder workOrder in found.workOrders {
            if workOrder.orderId != orderId {
                continue;
            }
            Task[] remaining = from Task task in workOrder.tasks
                where task.taskId != taskId
                select task;
            if remaining.length() == workOrder.tasks.length() {
                return error NotFoundError("Work order '" + orderId + "' has no task '" + taskId + "'");
            }
            workOrder.tasks = remaining;
            return found.clone();
        }
        return error NotFoundError("Asset '" + assetTag + "' has no work order '" + orderId + "'");
    }
}

// ---------------------------------- loans ------------------------------------

isolated function loanAsset(string assetTag, LoanRequest request)
        returns Asset|NotFoundError|ConflictError|ValidationError {
    if request.borrower.trim() == "" {
        return error ValidationError("'borrower' is required");
    }
    if !isValidDate(request.dueDate) {
        return error ValidationError("'dueDate' must be a calendar date in YYYY-MM-DD form");
    }
    string loanId = nextId("LN");
    string loanDate = today();
    lock {
        Asset? found = assetsByTag[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        if found.status != AVAILABLE {
            return error ConflictError("Asset '" + assetTag + "' is currently " + found.status
                    + " and cannot be loaned out");
        }
        found.currentLoan = {
            loanId: loanId,
            borrower: request.borrower,
            loanDate: loanDate,
            dueDate: request.dueDate
        };
        found.status = LOANED_OUT;
        return found.clone();
    }
}

isolated function returnAsset(string assetTag) returns Asset|NotFoundError|ConflictError {
    string returnDate = today();
    lock {
        Asset? found = assetsByTag[assetTag];
        if found is () {
            return error NotFoundError("No asset found with tag '" + assetTag + "'");
        }
        Loan? loan = found.currentLoan;
        if loan is () || found.status != LOANED_OUT {
            return error ConflictError("Asset '" + assetTag + "' is not currently on loan");
        }
        loan.returnedDate = returnDate;
        found.currentLoan = ();
        found.status = AVAILABLE;
        return found.clone();
    }
}

// -------------------------- maintenance / overdue -----------------------------

// Every maintenance, servicing or inspection schedule whose due date has
// passed (booking entries are excluded - they are occupancy, not upkeep).
isolated function overdueSchedules() returns OverdueEntry[] {
    string now = today();
    lock {
        OverdueEntry[] entries = [];
        foreach Asset asset in assetsByTag {
            if asset.status == DISPOSED {
                continue;
            }
            foreach Schedule schedule in asset.schedules {
                if schedule.'type == BOOKING {
                    continue;
                }
                int|error elapsed = daysBetween(schedule.dueDate, now);
                if elapsed is error || elapsed <= 0 {
                    continue;
                }
                entries.push({
                    assetTag: asset.assetTag,
                    name: asset.name,
                    institution: asset.institution,
                    site: asset.site,
                    status: asset.status,
                    scheduleId: schedule.scheduleId,
                    scheduleType: schedule.'type,
                    dueDate: schedule.dueDate,
                    daysOverdue: elapsed,
                    description: schedule.description
                });
            }
        }
        return entries.clone();
    }
}

// Every asset still on loan past its due date.
isolated function overdueLoans() returns OverdueLoan[] {
    string now = today();
    lock {
        OverdueLoan[] entries = [];
        foreach Asset asset in assetsByTag {
            Loan? loan = asset.currentLoan;
            if loan is () {
                continue;
            }
            int|error elapsed = daysBetween(loan.dueDate, now);
            if elapsed is error || elapsed <= 0 {
                continue;
            }
            entries.push({
                assetTag: asset.assetTag,
                name: asset.name,
                institution: asset.institution,
                borrower: loan.borrower,
                dueDate: loan.dueDate,
                daysOverdue: elapsed
            });
        }
        return entries.clone();
    }
}
