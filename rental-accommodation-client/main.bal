import ballerina/grpc;
import ballerina/io;

// ---------------------------------------------------------------------------
// Console client for the rental accommodation gRPC service.
// A menu-driven demonstration of every RPC in rental.proto: plain
// request/response calls, the create_users client-streaming RPC, and the
// list_available_properties server-streaming RPC.
// ---------------------------------------------------------------------------

const string SERVER_URL = "http://localhost:9090";

public function main() returns error? {
    io:println("=======================================================");
    io:println(" Ministry of Tourism - Rental Accommodation gRPC Client");
    io:println("=======================================================");

    RentalServiceClient|grpc:Error clientResult = new (SERVER_URL);
    if clientResult is grpc:Error {
        io:println("Cannot reach the rental service at " + SERVER_URL);
        io:println("Start the server first: cd rental-accommodation-server && bal run");
        return;
    }
    RentalServiceClient rentalClient = clientResult;

    boolean running = true;
    while running {
        printMenu();
        string choice = io:readln("Choose an option: ").trim();
        error? outcome = ();
        if choice == "1" {
            outcome = addHostFlow(rentalClient);
        } else if choice == "2" {
            outcome = addGuestFlow(rentalClient);
        } else if choice == "3" {
            outcome = addPropertyFlow(rentalClient);
        } else if choice == "4" {
            outcome = updatePropertyFlow(rentalClient);
        } else if choice == "5" {
            outcome = removePropertyFlow(rentalClient);
        } else if choice == "6" {
            outcome = createUsersFlow(rentalClient);
        } else if choice == "7" {
            outcome = listAvailableFlow(rentalClient);
        } else if choice == "8" {
            outcome = searchPropertyFlow(rentalClient);
        } else if choice == "9" {
            outcome = bookPropertyFlow(rentalClient);
        } else if choice == "10" {
            outcome = confirmBookingFlow(rentalClient);
        } else if choice == "11" {
            outcome = cancelBookingFlow(rentalClient);
        } else if choice == "12" {
            outcome = ratePropertyFlow(rentalClient);
        } else if choice == "0" {
            running = false;
            continue;
        } else {
            io:println("Unrecognised option.");
        }
        if outcome is error {
            report(outcome);
        }
        io:println("");
    }

    io:println("Goodbye.");
}

function printMenu() {
    io:println("");
    io:println("1) Add a host");
    io:println("2) Add a guest");
    io:println("3) Add property");
    io:println("4) Update property");
    io:println("5) Remove property");
    io:println("6) Register users from a batch    (client streaming)");
    io:println("7) List available properties       (server streaming)");
    io:println("8) Search property by id");
    io:println("9) Book a property");
    io:println("10) Confirm booking(s)");
    io:println("11) Cancel a booking");
    io:println("12) Rate a property");
    io:println("0) Exit");
}

// ----------------------------------------------------------------- unary UX

function addPropertyFlow(RentalServiceClient rentalClient) returns error? {
    string hostId = io:readln("host_id: ").trim();
    string title = io:readln("title: ").trim();
    string location = io:readln("location: ").trim();
    string region = io:readln("region: ").trim();
    string category = io:readln("category (APARTMENT/GUESTHOUSE/LODGE/CAMPSITE/HOUSE): ").trim();
    float rate = check parseFloatOrZero(io:readln("nightly_rate: ").trim());
    int guests = check parseIntOrZero(io:readln("max_guests: ").trim());
    string summary = io:readln("summary: ").trim();

    AddPropertyResponse response = check rentalClient->add_property({
        host_id: hostId,
        title,
        location,
        region,
        category,
        nightly_rate: rate,
        listing_status: "AVAILABLE",
        max_guests: guests,
        summary
    });
    io:println(response.details + (response.success ? " (property_id=" + response.property_id + ")" : ""));
}

function updatePropertyFlow(RentalServiceClient rentalClient) returns error? {
    string propertyId = io:readln("property_id: ").trim();
    string hostId = io:readln("host_id (owner): ").trim();
    string nightlyRateInput = io:readln("new nightly_rate (blank = unchanged): ").trim();
    string statusInput = io:readln("new listing_status (AVAILABLE/UNAVAILABLE, blank = unchanged): ").trim();

    UpdatePropertyResponse response = check rentalClient->update_property({
        property_id: propertyId,
        host_id: hostId,
        title: "",
        location: "",
        region: "",
        category: "",
        nightly_rate: check parseFloatOrZero(nightlyRateInput),
        listing_status: statusInput,
        max_guests: 0,
        summary: ""
    });
    io:println(response.details);
}

function removePropertyFlow(RentalServiceClient rentalClient) returns error? {
    string propertyId = io:readln("property_id: ").trim();
    string hostId = io:readln("host_id (owner): ").trim();
    RemovePropertyResponse response = check rentalClient->remove_property({property_id: propertyId, host_id: hostId});
    io:println(response.details);
    foreach Property p in response.remaining_properties {
        io:println("  remaining: " + p.property_id + " " + p.title);
    }
}

function searchPropertyFlow(RentalServiceClient rentalClient) returns error? {
    string propertyId = io:readln("property_id: ").trim();
    SearchPropertyResponse response = check rentalClient->search_property({property_id: propertyId});
    io:println(response.details);
    if response.available {
        printProperty(response.property);
    }
}

function bookPropertyFlow(RentalServiceClient rentalClient) returns error? {
    string guestId = io:readln("guest_id: ").trim();
    string propertyId = io:readln("property_id: ").trim();
    string checkIn = io:readln("check_in (YYYY-MM-DD): ").trim();
    string checkOut = io:readln("check_out (YYYY-MM-DD): ").trim();
    int guests = check parseIntOrZero(io:readln("guests: ").trim());

    BookPropertyResponse response = check rentalClient->book_property({
        guest_id: guestId,
        property_id: propertyId,
        check_in: checkIn,
        check_out: checkOut,
        guests
    });
    io:println(response.details);
    if response.accepted {
        io:println("cart_item_id=" + response.cart_item_id + "  nights=" + response.nights.toString()
                + "  estimated_total=N$" + response.estimated_total.toString());
    }
}

function confirmBookingFlow(RentalServiceClient rentalClient) returns error? {
    string guestId = io:readln("guest_id: ").trim();
    string cartItemId = io:readln("cart_item_id (blank = confirm entire cart): ").trim();

    ConfirmBookingResponse response = check rentalClient->confirm_booking({guest_id: guestId, cart_item_id: cartItemId});
    io:println(response.details + "  grand_total=N$" + response.grand_total.toString());
    foreach Booking b in response.bookings {
        io:println("  confirmed: " + b.booking_id + " " + b.property_title + " " + b.check_in + " -> " + b.check_out);
    }
    foreach string reason in response.rejections {
        io:println("  rejected: " + reason);
    }
}

function cancelBookingFlow(RentalServiceClient rentalClient) returns error? {
    string guestId = io:readln("guest_id: ").trim();
    string bookingId = io:readln("booking_id: ").trim();
    CancelBookingResponse response = check rentalClient->cancel_booking({guest_id: guestId, booking_id: bookingId});
    io:println(response.details);
}

function ratePropertyFlow(RentalServiceClient rentalClient) returns error? {
    string guestId = io:readln("guest_id: ").trim();
    string propertyId = io:readln("property_id: ").trim();
    int rating = check parseIntOrZero(io:readln("rating (1-5): ").trim());
    string review = io:readln("review (optional): ").trim();

    RatePropertyResponse response = check rentalClient->rate_property({
        guest_id: guestId,
        property_id: propertyId,
        rating,
        review
    });
    io:println(response.details);
    if response.accepted {
        io:println("  new average_rating=" + response.average_rating.toString() + " (" + response.rating_count.toString() + " rating(s))");
    }
}

// ---------------------------------------------------------- server streaming

function listAvailableFlow(RentalServiceClient rentalClient) returns error? {
    // location and region are separate Property fields (a city versus a
    // broader region), but the server matches one "place" term against
    // either of them, so a single prompt here is enough.
    string place = io:readln("filter by location or region (blank = any): ").trim();
    int guests = check parseIntOrZero(io:readln("minimum guests (blank = any): ").trim());

    stream<Property, grpc:Error?> propStream = check rentalClient->list_available_properties({
        location: place,
        region: "",
        min_rate: 0.0,
        max_rate: 0.0,
        guests,
        check_in: "",
        check_out: ""
    });

    check propStream.forEach(function(Property p) {
        printProperty(p);
    });
    io:println("(properties streamed above)");
}

// ------------------------------------------- single-user client streaming

// Registers exactly one Host by sending a batch of one profile through the
// same create_users client-streaming RPC that option 6 uses for many. A
// dedicated menu entry makes the common case - adding one person - a single
// set of prompts instead of the "type done to finish" batch flow.
function addHostFlow(RentalServiceClient rentalClient) returns error? {
    return addSingleUserFlow(rentalClient, "HOST");
}

function addGuestFlow(RentalServiceClient rentalClient) returns error? {
    return addSingleUserFlow(rentalClient, "GUEST");
}

function addSingleUserFlow(RentalServiceClient rentalClient, string accountType) returns error? {
    string userId = io:readln("user_id: ").trim();
    string fullName = io:readln("full_name: ").trim();
    string email = io:readln("email: ").trim();
    string phone = io:readln("phone: ").trim();

    UserProfile[] batch = [
        {user_id: userId, full_name: fullName, email, account_type: accountType, phone}
    ];
    CreateUsersResponse response = check streamUsers(rentalClient, batch);
    io:println(response.details);
    foreach string rejection in response.rejections {
        io:println("  rejected: " + rejection);
    }
}

// ---------------------------------------------------------- client streaming

function createUsersFlow(RentalServiceClient rentalClient) returns error? {
    UserProfile[] batch = [];
    io:println("Enter user profiles, one per line. Type 'done' as the user_id to finish.");
    boolean collecting = true;
    while collecting {
        string userId = io:readln("user_id: ").trim();
        if userId.equalsIgnoreCaseAscii("done") {
            collecting = false;
            continue;
        }
        string fullName = io:readln("  full_name: ").trim();
        string email = io:readln("  email: ").trim();
        string accountType = io:readln("  account_type (HOST/GUEST): ").trim();
        string phone = io:readln("  phone: ").trim();
        batch.push({user_id: userId, full_name: fullName, email, account_type: accountType, phone});
    }

    if batch.length() == 0 {
        io:println("No users entered.");
        return;
    }

    CreateUsersResponse response = check streamUsers(rentalClient, batch);
    io:println(response.details);
    foreach string rejection in response.rejections {
        io:println("  rejected: " + rejection);
    }
}

function streamUsers(RentalServiceClient rentalClient, UserProfile[] batch) returns CreateUsersResponse|error {
    Create_usersStreamingClient streamingClient = check rentalClient->create_users();
    foreach UserProfile profile in batch {
        check streamingClient->sendUserProfile(profile);
    }
    check streamingClient->complete();
    CreateUsersResponse? response = check streamingClient->receiveCreateUsersResponse();
    if response is () {
        return error("The server closed the create_users stream without a response");
    }
    return response;
}

// --------------------------------------------------------------- utilities

function printProperty(Property p) {
    string ratingInfo = p.rating_count > 0
        ? "  rating=" + p.average_rating.toString() + " (" + p.rating_count.toString() + ")"
        : "  rating=unrated";
    io:println("  " + p.property_id + "  " + p.title + "  " + p.location + "/" + p.region
            + "  " + p.category + "  N$" + p.nightly_rate.toString() + "/night  max_guests=" + p.max_guests.toString()
            + "  [" + p.listing_status + "]" + ratingInfo);
}

function parseFloatOrZero(string value) returns float|error {
    if value == "" {
        return 0.0;
    }
    return check float:fromString(value);
}

function parseIntOrZero(string value) returns int|error {
    if value == "" {
        return 0;
    }
    return check int:fromString(value);
}

function report(error err) {
    if err is grpc:Error {
        io:println("gRPC call failed: " + err.message());
    } else {
        io:println("Error: " + err.message());
    }
}
