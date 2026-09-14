import ballerina/grpc;
import ballerina/log;

// ---------------------------------------------------------------------------
// gRPC service for the Ministry of Tourism rental accommodation system.
// Demonstrates all four RPC styles: unary (add_property, update_property,
// remove_property, search_property, book_property, confirm_booking),
// client streaming (create_users) and server streaming
// (list_available_properties).
// ---------------------------------------------------------------------------

const string STATUS_AVAILABLE = "AVAILABLE";
const string STATUS_UNAVAILABLE = "UNAVAILABLE";
const string BOOKING_CONFIRMED = "CONFIRMED";

listener grpc:Listener rentalListener = new (9090);

@grpc:Descriptor {value: RENTAL_DESC}
service "RentalService" on rentalListener {

    function init() {
        log:printInfo("Rental accommodation gRPC service started on port 9090. No hosts, guests, or properties exist yet - register them through create_users and add_property.");
    }

    // --------------------------------------------------------------- unary --

    remote function add_property(AddPropertyRequest value) returns AddPropertyResponse|error {
        if !userIsHost(value.host_id) {
            return {success: false, property_id: "", details: "host_id '" + value.host_id + "' is not a registered host"};
        }
        if value.title.trim() == "" || value.location.trim() == "" {
            return {success: false, property_id: "", details: "title and location are required"};
        }
        if value.nightly_rate <= 0.0 {
            return {success: false, property_id: "", details: "nightly_rate must be positive"};
        }

        string listingStatus = value.listing_status.trim() == "" ? STATUS_AVAILABLE : value.listing_status.toUpperAscii();
        Property property = {
            property_id: nextId("PROP"),
            host_id: value.host_id,
            title: value.title,
            location: value.location,
            region: value.region,
            category: value.category.toUpperAscii(),
            nightly_rate: round2(value.nightly_rate),
            listing_status: listingStatus,
            max_guests: value.max_guests,
            summary: value.summary,
            average_rating: 0.0,
            rating_count: 0
        };
        Property saved = addProperty(property);
        return {success: true, property_id: saved.property_id, details: "Property listed successfully"};
    }

    remote function update_property(UpdatePropertyRequest value) returns UpdatePropertyResponse|error {
        Property|NotFoundError existing = getProperty(value.property_id);
        if existing is NotFoundError {
            return {success: false, details: existing.message(), property: emptyProperty()};
        }
        if existing.host_id != value.host_id {
            return {success: false, details: "host_id does not own property '" + value.property_id + "'", property: existing};
        }

        Property updated = existing.clone();
        if value.title.trim() != "" {
            updated.title = value.title;
        }
        if value.location.trim() != "" {
            updated.location = value.location;
        }
        if value.region.trim() != "" {
            updated.region = value.region;
        }
        if value.category.trim() != "" {
            updated.category = value.category.toUpperAscii();
        }
        if value.nightly_rate > 0.0 {
            updated.nightly_rate = round2(value.nightly_rate);
        }
        if value.listing_status.trim() != "" {
            updated.listing_status = value.listing_status.toUpperAscii();
        }
        if value.max_guests > 0 {
            updated.max_guests = value.max_guests;
        }
        if value.summary.trim() != "" {
            updated.summary = value.summary;
        }

        Property saved = replaceProperty(updated);
        return {success: true, details: "Property updated successfully", property: saved};
    }

    remote function remove_property(RemovePropertyRequest value) returns RemovePropertyResponse|error {
        Property|NotFoundError existing = getProperty(value.property_id);
        if existing is NotFoundError {
            return {success: false, details: existing.message(), remaining_properties: []};
        }
        if existing.host_id != value.host_id {
            return {success: false, details: "host_id does not own property '" + value.property_id + "'", remaining_properties: []};
        }

        string region = existing.region;
        Property|NotFoundError removed = removeProperty(value.property_id);
        if removed is NotFoundError {
            return {success: false, details: removed.message(), remaining_properties: []};
        }
        Property[] remaining = availableInRegion(region);
        return {success: true, details: "Property removed successfully", remaining_properties: remaining};
    }

    remote function search_property(SearchPropertyRequest value) returns SearchPropertyResponse|error {
        Property|NotFoundError found = getProperty(value.property_id);
        if found is NotFoundError {
            return {available: false, details: found.message(), property: emptyProperty()};
        }
        boolean available = found.listing_status == STATUS_AVAILABLE;
        string details = available ? "Property is available" : "Property is currently unavailable";
        return {available, details, property: found};
    }

    remote function book_property(BookPropertyRequest value) returns BookPropertyResponse|error {
        UserProfile|NotFoundError guest = getUser(value.guest_id);
        if guest is NotFoundError {
            return {accepted: false, details: guest.message(), cart_item_id: "", nights: 0, estimated_total: 0.0};
        }
        Property|NotFoundError property = getProperty(value.property_id);
        if property is NotFoundError {
            return {accepted: false, details: property.message(), cart_item_id: "", nights: 0, estimated_total: 0.0};
        }
        if property.listing_status != STATUS_AVAILABLE {
            return {accepted: false, details: "Property is not currently available", cart_item_id: "", nights: 0, estimated_total: 0.0};
        }
        if value.guests > property.max_guests {
            return {
                accepted: false,
                details: "Property accommodates at most " + property.max_guests.toString() + " guests",
                cart_item_id: "",
                nights: 0,
                estimated_total: 0.0
            };
        }
        if !isValidDate(value.check_in) || !isValidDate(value.check_out) {
            return {accepted: false, details: "check_in and check_out must be valid dates (YYYY-MM-DD)", cart_item_id: "", nights: 0, estimated_total: 0.0};
        }

        int|error nights = nightsBetween(value.check_in, value.check_out);
        if nights is error || nights <= 0 {
            return {accepted: false, details: "check_out must be after check_in", cart_item_id: "", nights: 0, estimated_total: 0.0};
        }

        boolean|error clash = hasOverlap(value.property_id, value.check_in, value.check_out);
        if clash is error {
            return {accepted: false, details: "Unable to validate dates", cart_item_id: "", nights: 0, estimated_total: 0.0};
        }
        if clash {
            return {accepted: false, details: "Property is already booked for an overlapping date range", cart_item_id: "", nights: 0, estimated_total: 0.0};
        }

        float total = round2(<float>nights * property.nightly_rate);
        CartItem item = {
            cartItemId: nextId("CART"),
            guestId: value.guest_id,
            propertyId: value.property_id,
            checkIn: value.check_in,
            checkOut: value.check_out,
            guests: value.guests,
            nights,
            nightlyRate: property.nightly_rate,
            total
        };
        CartItem saved = addCartItem(item);
        return {
            accepted: true,
            details: "Added to booking cart; confirm to finalize",
            cart_item_id: saved.cartItemId,
            nights: saved.nights,
            estimated_total: saved.total
        };
    }

    remote function confirm_booking(ConfirmBookingRequest value) returns ConfirmBookingResponse|error {
        CartItem[] candidates;
        if value.cart_item_id.trim() == "" {
            candidates = cartItemsForGuest(value.guest_id);
        } else {
            CartItem|NotFoundError item = getCartItem(value.cart_item_id);
            if item is NotFoundError {
                return {confirmed: false, details: item.message(), bookings: [], grand_total: 0.0, rejections: [item.message()]};
            }
            if item.guestId != value.guest_id {
                string reason = "cart item '" + value.cart_item_id + "' does not belong to guest '" + value.guest_id + "'";
                return {confirmed: false, details: reason, bookings: [], grand_total: 0.0, rejections: [reason]};
            }
            candidates = [item];
        }

        if candidates.length() == 0 {
            return {confirmed: false, details: "No items in the booking cart", bookings: [], grand_total: 0.0, rejections: []};
        }

        Booking[] confirmed = [];
        string[] rejections = [];
        float grandTotal = 0.0;

        foreach CartItem item in candidates {
            boolean|error clash = hasOverlap(item.propertyId, item.checkIn, item.checkOut);
            if clash is error || clash {
                // Left in the cart on purpose: the Guest can adjust the dates
                // and retry without re-entering the whole request.
                rejections.push("Cart item '" + item.cartItemId + "' clashes with an existing booking");
                continue;
            }
            Property|NotFoundError property = getProperty(item.propertyId);
            if property is NotFoundError {
                rejections.push("Cart item '" + item.cartItemId + "' refers to a property that no longer exists");
                removeCartItem(item.cartItemId);
                continue;
            }

            Booking booking = {
                booking_id: nextId("BKG"),
                property_id: item.propertyId,
                property_title: property.title,
                guest_id: item.guestId,
                check_in: item.checkIn,
                check_out: item.checkOut,
                nights: item.nights,
                nightly_rate: item.nightlyRate,
                total_cost: item.total,
                booking_status: BOOKING_CONFIRMED
            };
            Booking saved = addBooking(booking);
            confirmed.push(saved);
            grandTotal = round2(grandTotal + saved.total_cost);
            removeCartItem(item.cartItemId);
        }

        boolean anyConfirmed = confirmed.length() > 0;
        string details = anyConfirmed
            ? confirmed.length().toString() + " booking(s) confirmed"
            : "No cart items could be confirmed";
        return {confirmed: anyConfirmed, details, bookings: confirmed, grand_total: grandTotal, rejections};
    }

    // Bonus RPC beyond the brief's minimum: completes the booking lifecycle
    // (book -> confirm -> cancel) by letting a Guest free up a confirmed
    // stay's dates again.
    remote function cancel_booking(CancelBookingRequest value) returns CancelBookingResponse|error {
        Booking|NotFoundError existing = getBooking(value.booking_id);
        if existing is NotFoundError {
            return {cancelled: false, details: existing.message()};
        }
        if existing.guest_id != value.guest_id {
            return {cancelled: false, details: "booking '" + value.booking_id + "' does not belong to guest '" + value.guest_id + "'"};
        }
        if existing.booking_status == "CANCELLED" {
            return {cancelled: false, details: "Booking is already cancelled"};
        }

        Booking cancelled = existing.clone();
        cancelled.booking_status = "CANCELLED";
        _ = updateBooking(cancelled);
        return {cancelled: true, details: "Booking '" + value.booking_id + "' cancelled; those dates are available again"};
    }

    // Bonus RPC beyond the brief's minimum: a Guest leaves a 1-5 rating (and
    // an optional review) for a property, building a running average that
    // shows up on every listing.
    remote function rate_property(RatePropertyRequest value) returns RatePropertyResponse|error {
        if value.rating < 1 || value.rating > 5 {
            return {accepted: false, details: "rating must be between 1 and 5", average_rating: 0.0, rating_count: 0};
        }
        Property|NotFoundError existing = getProperty(value.property_id);
        if existing is NotFoundError {
            return {accepted: false, details: existing.message(), average_rating: 0.0, rating_count: 0};
        }

        int newCount = existing.rating_count + 1;
        float priorTotal = existing.average_rating * <float>existing.rating_count;
        float newAverage = round2((priorTotal + <float>value.rating) / <float>newCount);

        Property updated = existing.clone();
        updated.average_rating = newAverage;
        updated.rating_count = newCount;
        _ = replaceProperty(updated);

        return {accepted: true, details: "Rating recorded", average_rating: newAverage, rating_count: newCount};
    }

    // ------------------------------------------------------- client stream --

    remote function create_users(stream<UserProfile, grpc:Error?> clientStream) returns CreateUsersResponse|error {
        int accepted = 0;
        int rejected = 0;
        string[] acceptedIds = [];
        string[] rejections = [];

        error? walkError = clientStream.forEach(function(UserProfile profile) {
            UserProfile|ValidationError|ConflictError result = addUser(profile);
            if result is UserProfile {
                accepted += 1;
                acceptedIds.push(result.user_id);
            } else {
                rejected += 1;
                rejections.push(profile.user_id + ": " + result.message());
            }
        });
        if walkError is error {
            return error("Failed while reading the incoming user stream: " + walkError.message());
        }

        string details = accepted.toString() + " user(s) accepted, " + rejected.toString() + " rejected";
        return {
            success: rejected == 0,
            accepted_count: accepted,
            rejected_count: rejected,
            accepted_user_ids: acceptedIds,
            rejections,
            details
        };
    }

    // ------------------------------------------------------- server stream --

    remote function list_available_properties(ListPropertiesRequest value) returns stream<Property, error?>|error {
        Property[] all = listProperties();
        Property[] matches = [];

        foreach Property p in all {
            if p.listing_status != STATUS_AVAILABLE {
                continue;
            }
            // location and region are separate fields on a Property (a city
            // versus a broader region), so a single "place" filter is matched
            // against either one rather than requiring both to match at once.
            string placeTerm = value.location.trim() != "" ? value.location : value.region;
            if placeTerm.trim() != "" && !(equalsIgnoreCase(p.location, placeTerm) || equalsIgnoreCase(p.region, placeTerm)) {
                continue;
            }
            if value.min_rate > 0.0 && p.nightly_rate < value.min_rate {
                continue;
            }
            if value.max_rate > 0.0 && p.nightly_rate > value.max_rate {
                continue;
            }
            if value.guests > 0 && p.max_guests < value.guests {
                continue;
            }
            if value.check_in.trim() != "" && value.check_out.trim() != "" {
                boolean|error clash = hasOverlap(p.property_id, value.check_in, value.check_out);
                if clash is error || clash {
                    continue;
                }
            }
            matches.push(p);
        }

        return matches.toStream();
    }
}

// ------------------------------------------------------------ helpers ------

isolated function hasOverlap(string propertyId, string checkIn, string checkOut) returns boolean|error {
    Booking[] existing = bookingsForProperty(propertyId);
    foreach Booking b in existing {
        boolean overlap = check staysOverlap(checkIn, checkOut, b.check_in, b.check_out);
        if overlap {
            return true;
        }
    }
    return false;
}

isolated function emptyProperty() returns Property => {
    property_id: "",
    host_id: "",
    title: "",
    location: "",
    region: "",
    category: "",
    nightly_rate: 0.0,
    listing_status: "",
    max_guests: 0,
    summary: "",
    average_rating: 0.0,
    rating_count: 0
};
