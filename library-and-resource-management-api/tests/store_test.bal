import ballerina/test;

// ---------------------------------------------------------------------------
// Unit tests for the data store and the date helpers. They run against the
// same in-memory store the service uses, seeded by `init()` before the first
// test executes. Each test that mutates shared seed data either targets a
// unique throwaway asset, or cleans up after itself, so results do not depend
// on execution order.
// ---------------------------------------------------------------------------

@test:Config {}
function testDateHelpers() returns error? {
    test:assertTrue(isValidDate("2026-09-01"), "a well formed date should be accepted");
    test:assertFalse(isValidDate("01-09-2026"), "day-first dates should be rejected");
    test:assertFalse(isValidDate("not-a-date"), "free text should be rejected");
    test:assertEquals(check daysBetween("2026-09-01", "2026-09-11"), 10);
    test:assertEquals(check daysBetween("2026-09-11", "2026-09-01"), -10);
    test:assertTrue(check rangesOverlap("2026-10-01", "2026-10-05", "2026-10-04", "2026-10-08"));
    test:assertFalse(check rangesOverlap("2026-10-01", "2026-10-05", "2026-10-05", "2026-10-08"),
            "a check-out on the check-in day is not a clash");
}

@test:Config {}
function testSeededCatalogue() {
    test:assertTrue(listInstitutions().length() >= 3, "the Ministry listing should be seeded");
    test:assertTrue(listAssets().length() >= 4, "the sample catalogue should be seeded");
}

@test:Config {}
function testAssetLifecycle() returns error? {
    Asset candidate = {
        assetTag: "TEST-LIFECYCLE-001",
        name: "Test Bench",
        institution: "University of Namibia",
        site: "Oshakati Campus",
        dateAcquired: "2025-01-01"
    };

    Asset created = check addAsset(candidate);
    test:assertEquals(created.assetTag, "TEST-LIFECYCLE-001");
    test:assertEquals(created.status, AVAILABLE);

    Asset fetched = check getAsset("TEST-LIFECYCLE-001");
    test:assertEquals(fetched.name, "Test Bench");

    Asset patched = check patchAsset("TEST-LIFECYCLE-001", {name: "Renamed Bench"});
    test:assertEquals(patched.name, "Renamed Bench");
    test:assertEquals(patched.site, "Oshakati Campus", "untouched fields must survive a patch");

    Asset replaced = check replaceAsset("TEST-LIFECYCLE-001", {
        assetTag: "ignored-in-favour-of-the-path",
        name: "Fully Replaced Bench",
        institution: "University of Namibia",
        site: "Main Campus - Windhoek",
        dateAcquired: "2025-06-01"
    });
    test:assertEquals(replaced.assetTag, "TEST-LIFECYCLE-001", "the path tag must win over the body tag");
    test:assertEquals(replaced.site, "Main Campus - Windhoek");

    Asset removed = check deleteAsset("TEST-LIFECYCLE-001");
    test:assertEquals(removed.assetTag, "TEST-LIFECYCLE-001");
    test:assertTrue(getAsset("TEST-LIFECYCLE-001") is NotFoundError);
}

@test:Config {}
function testDuplicateTagIsRejected() returns error? {
    Asset candidate = {
        assetTag: "TEST-DUPLICATE-001",
        name: "First",
        institution: "University of Namibia",
        site: "Oshakati Campus",
        dateAcquired: "2025-01-01"
    };
    _ = check addAsset(candidate);
    Asset|error second = addAsset(candidate);
    test:assertTrue(second is ConflictError, "assetTag must be unique");
    _ = check deleteAsset("TEST-DUPLICATE-001");
}

@test:Config {}
function testUnknownInstitutionIsRejected() {
    Asset|error result = addAsset({
        assetTag: "TEST-BAD-INST",
        name: "Orphan",
        institution: "School of Nowhere",
        site: "Nowhere",
        dateAcquired: "2025-01-01"
    });
    test:assertTrue(result is ValidationError);
}

@test:Config {}
function testLoanAndReturn() returns error? {
    Asset loaned = check loanAsset("NUST-LIB-BK-1042", {borrower: "220012345", dueDate: "2026-12-31"});
    test:assertEquals(loaned.status, LOANED_OUT);

    Asset|error again = loanAsset("NUST-LIB-BK-1042", {borrower: "220054321", dueDate: "2026-12-31"});
    test:assertTrue(again is ConflictError, "an asset already on loan cannot be loaned again");

    Asset returned = check returnAsset("NUST-LIB-BK-1042");
    test:assertEquals(returned.status, AVAILABLE);
    test:assertTrue(returned.currentLoan is ());
}

@test:Config {}
function testBookingClashIsRejected() returns error? {
    Asset booked = check bookAsset("UNAM-LAB-ROOM-07",
            {bookedBy: "Dr Shikongo", startDate: "2026-11-02", endDate: "2026-11-06"});
    test:assertEquals(booked.status, OCCUPIED);

    Asset|error clash = bookAsset("UNAM-LAB-ROOM-07",
            {bookedBy: "Ms Amutenya", startDate: "2026-11-05", endDate: "2026-11-09"});
    test:assertTrue(clash is ConflictError, "overlapping bookings must be refused");

    Asset accepted = check bookAsset("UNAM-LAB-ROOM-07",
            {bookedBy: "Ms Amutenya", startDate: "2026-11-06", endDate: "2026-11-09"});
    test:assertEquals(accepted.schedules.length(), 2, "a booking starting on another's end date is not a clash");
}

@test:Config {}
function testWorkOrderClosesAndFreesAsset() returns error? {
    Asset opened = check addWorkOrder("NUST-LIB-3DP-001",
            {orderId: "", description: "Nozzle heat-bed failure"});
    test:assertEquals(opened.status, UNDER_MAINTENANCE);
    string orderId = opened.workOrders[opened.workOrders.length() - 1].orderId;

    Asset withTask = check addTask("NUST-LIB-3DP-001", orderId,
            {taskId: "", description: "Check thermal sensor connectivity."});
    WorkOrder last = withTask.workOrders[withTask.workOrders.length() - 1];
    test:assertEquals(last.tasks.length(), 1);

    Asset closed = check updateWorkOrder("NUST-LIB-3DP-001", orderId, {status: CLOSED});
    test:assertEquals(closed.status, AVAILABLE, "closing the last open work order frees the asset");
}

@test:Config {}
function testComponentLifecycle() returns error? {
    Asset withComponent = check addComponent("NUST-LIB-3DP-001",
            {compId: "TEST-COMP-1", name: "Test Extruder Fan"});
    test:assertTrue(hasComponent(withComponent, "TEST-COMP-1"));

    Asset|error conflictResult = addComponent("NUST-LIB-3DP-001", {compId: "TEST-COMP-1", name: "Duplicate"});
    test:assertTrue(conflictResult is ConflictError, "compId must be unique per asset");

    Asset withoutComponent = check removeComponent("NUST-LIB-3DP-001", "TEST-COMP-1");
    test:assertFalse(hasComponent(withoutComponent, "TEST-COMP-1"));
}

function hasComponent(Asset asset, string compId) returns boolean {
    foreach Component component in asset.components {
        if component.compId == compId {
            return true;
        }
    }
    return false;
}

@test:Config {}
function testMaintenanceOverdueDetection() returns error? {
    _ = check addSchedule("NUST-LIB-3DP-001", {
        scheduleId: "TEST-SCH-PAST",
        'type: MAINTENANCE,
        dueDate: "2020-01-01",
        description: "Deliberately elapsed schedule"
    });
    OverdueEntry[] overdue = overdueSchedules();
    OverdueEntry[] matching = from OverdueEntry entry in overdue
        where entry.scheduleId == "TEST-SCH-PAST"
        select entry;
    test:assertEquals(matching.length(), 1);
    test:assertTrue(matching[0].daysOverdue > 0);
    _ = check removeSchedule("NUST-LIB-3DP-001", "TEST-SCH-PAST");
}

@test:Config {}
function testInstitutionCannotBeRemovedWhileInUse() {
    Institution|error result = removeInstitution("NUST");
    test:assertTrue(result is ConflictError, "an institution that still owns assets must not be removable");
}

@test:Config {}
function testFilterByInstitutionAndSite() {
    Asset[] unam = filterAssets("University of Namibia", (), ());
    test:assertTrue(unam.length() >= 2);
    Asset[] oshakati = filterAssets("University of Namibia", "Oshakati Campus", ());
    test:assertTrue(oshakati.length() >= 1);
    foreach Asset asset in oshakati {
        test:assertEquals(asset.site, "Oshakati Campus");
    }
}

@test:Config {}
function testInstitutionSiteManagement() returns error? {
    Institution added = check addInstitution({institutionId: "TEST-INST", name: "Test Institute of Testing"});
    test:assertEquals(added.sites.length(), 0);

    Institution withSite = check addSite("TEST-INST", "Main Campus");
    test:assertEquals(withSite.sites.length(), 1);

    Institution|error duplicateSite = addSite("TEST-INST", "Main Campus");
    test:assertTrue(duplicateSite is ConflictError, "the same site cannot be listed twice");

    Institution removed = check removeInstitution("TEST-INST");
    test:assertEquals(removed.institutionId, "TEST-INST");
}
