// ---------------------------------------------------------------------------
// In-memory data layer for the rental service.
// Four isolated maps back the four entity kinds; every lock block below
// touches exactly one of them, since Ballerina forbids a single lock
// statement from accessing more than one isolated/restricted variable.
// ---------------------------------------------------------------------------

type NotFoundError distinct error;
type ConflictError distinct error;
type ValidationError distinct error;

type CartItem record {|
    string cartItemId;
    string guestId;
    string propertyId;
    string checkIn;
    string checkOut;
    int guests;
    int nights;
    float nightlyRate;
    float total;
|};

isolated map<UserProfile> userStore = {};
isolated map<Property> propertyStore = {};
isolated map<Booking> bookingStore = {};
isolated map<CartItem> cartStore = {};

// ------------------------------- users --------------------------------------

isolated function addUser(UserProfile profile) returns UserProfile|ValidationError|ConflictError {
    string userId = profile.user_id;
    if userId.trim() == "" {
        return error ValidationError("user_id is required");
    }
    if profile.full_name.trim() == "" {
        return error ValidationError("full_name is required");
    }
    string accountType = profile.account_type.toUpperAscii();
    if accountType != "HOST" && accountType != "GUEST" {
        return error ValidationError("account_type must be HOST or GUEST, got '" + profile.account_type + "'");
    }
    lock {
        if userStore.hasKey(userId) {
            return error ConflictError("A user with id '" + userId + "' already exists");
        }
        UserProfile stored = profile.clone();
        stored.account_type = accountType;
        userStore[userId] = stored;
        return stored.clone();
    }
}

isolated function getUser(string userId) returns UserProfile|NotFoundError {
    lock {
        UserProfile? found = userStore[userId];
        if found is () {
            return error NotFoundError("No user with id '" + userId + "'");
        }
        return found.clone();
    }
}

isolated function userIsHost(string userId) returns boolean {
    lock {
        UserProfile? found = userStore[userId];
        return found is UserProfile && found.account_type == "HOST";
    }
}

// ----------------------------- properties ------------------------------------

isolated function addProperty(Property property) returns Property {
    lock {
        propertyStore[property.property_id] = property.clone();
        return property.clone();
    }
}

isolated function getProperty(string propertyId) returns Property|NotFoundError {
    lock {
        Property? found = propertyStore[propertyId];
        if found is () {
            return error NotFoundError("No property with id '" + propertyId + "'");
        }
        return found.clone();
    }
}

isolated function replaceProperty(Property property) returns Property {
    lock {
        propertyStore[property.property_id] = property.clone();
        return property.clone();
    }
}

isolated function removeProperty(string propertyId) returns Property|NotFoundError {
    lock {
        if !propertyStore.hasKey(propertyId) {
            return error NotFoundError("No property with id '" + propertyId + "'");
        }
        Property removed = propertyStore.remove(propertyId);
        return removed.clone();
    }
}

isolated function availableInRegion(string region) returns Property[] {
    lock {
        // Same pattern as the other query-based store functions: a typed
        // intermediate array plus an outer .clone() satisfies both the
        // map-source type-inference rule and the lock-transfer isolation rule.
        Property[] matches = from Property p in propertyStore
            where equalsIgnoreCase(p.region, region) && p.listing_status == "AVAILABLE"
            select p;
        return matches.clone();
    }
}

isolated function listProperties() returns Property[] {
    lock {
        return propertyStore.toArray().clone();
    }
}

// ------------------------------- bookings -------------------------------------

isolated function bookingsForProperty(string propertyId) returns Booking[] {
    lock {
        Booking[] matches = from Booking b in bookingStore
            where b.property_id == propertyId && b.booking_status != "CANCELLED"
            select b;
        return matches.clone();
    }
}

isolated function addBooking(Booking booking) returns Booking {
    lock {
        bookingStore[booking.booking_id] = booking.clone();
        return booking.clone();
    }
}

isolated function getBooking(string bookingId) returns Booking|NotFoundError {
    lock {
        Booking? found = bookingStore[bookingId];
        if found is () {
            return error NotFoundError("No booking with id '" + bookingId + "'");
        }
        return found.clone();
    }
}

isolated function updateBooking(Booking booking) returns Booking {
    lock {
        bookingStore[booking.booking_id] = booking.clone();
        return booking.clone();
    }
}

// --------------------------------- cart ----------------------------------------

isolated function addCartItem(CartItem item) returns CartItem {
    lock {
        cartStore[item.cartItemId] = item.clone();
        return item.clone();
    }
}

isolated function getCartItem(string cartItemId) returns CartItem|NotFoundError {
    lock {
        CartItem? found = cartStore[cartItemId];
        if found is () {
            return error NotFoundError("No cart item with id '" + cartItemId + "'");
        }
        return found.clone();
    }
}

isolated function removeCartItem(string cartItemId) {
    lock {
        _ = cartStore.removeIfHasKey(cartItemId);
    }
}

isolated function cartItemsForGuest(string guestId) returns CartItem[] {
    lock {
        CartItem[] matches = from CartItem c in cartStore
            where c.guestId == guestId
            select c;
        return matches.clone();
    }
}
