# DSA612S — Assignment 1

**Distributed Systems and Applications · Namibia University of Science and Technology**

| | |
|---|---|
| Student | *[Your Name]* |
| Student number | *[Student Number]* |
| Programme | Bachelor of Computer Science |
| Lecturer | Mr H. Kandjimi |
| Due | 14 September 2026, 23:59 |

Two independent distributed systems, both written in Ballerina Swan Lake:

* **Question 1 — Distributed Library and Resource Management System.** A RESTful
  backend for the Ministry of Higher Education, Training and Innovations, with a
  command-line Ballerina client and a browser console.
* **Question 2 — Rental Accommodation System.** A gRPC service for the Ministry
  of Tourism defined by a Protocol Buffer contract, with a Ballerina gRPC client
  that exercises simple, client-streaming and server-streaming calls.

---

## 1. Repository layout

```
DSA612S-Assignment1/
├── README.md                       this file
├── docs/
│   ├── DESIGN.md                   architecture and design decisions
│   └── api-reference.md            full REST endpoint reference with examples
├── proto/
│   └── rental.proto                Question 2 service contract
├── library-and-resource-management-api/     Q1 · Ballerina REST backend
│   ├── types.bal                   domain model
│   ├── store.bal                   in-memory data store (map + table)
│   ├── service.bal                 the REST service
│   ├── ui_service.bal              serves the browser console
│   ├── utils.bal                   date and identifier helpers
│   ├── resources/index.html        browser console (bonus web interface)
│   └── tests/store_test.bal        unit tests
├── library-and-resource-management-client/  Q1 · Ballerina command-line client
├── rental-accommodation-server/  Q2 · Ballerina gRPC server
├── rental-accommodation-client/  Q2 · Ballerina gRPC client
└── scripts/
    ├── generate-stubs.sh           generates rental_pb.bal (Linux/macOS)
    └── generate-stubs.bat          the same, for Windows
```

Each of the four directories above is a self-contained Ballerina package
with its own `Ballerina.toml`, so the four processes build, run and fail
independently — which is the point of the exercise.

---

## 2. Prerequisites

* **Ballerina Swan Lake** 2201.10.0 or newer — <https://ballerina.io/downloads/>
  (`bal version` should print a 2201.x distribution).
* Java 17+ is bundled with the Ballerina installer; nothing else is needed.
* A browser for the Question 1 console, and optionally `curl` for the REST
  examples in [`docs/api-reference.md`](docs/api-reference.md).

No database is required: both systems keep state in memory, as the brief
specifies.

---

## 3. Question 1 — Library and Resource Management System

### 3.1 Start the backend

```bash
cd library-and-resource-management-api
bal run
```

The service starts on **port 8080** and seeds itself with three registered
institutions and four sample assets, so there is something to look at
immediately.

* REST API — `http://localhost:8080/library`
* Browser console — `http://localhost:8080/`
* Health check — `http://localhost:8080/library/health`

> Start the service from *inside* `library-and-resource-management-api`: the console page is
> read from `resources/index.html` relative to the working directory.

A different port can be supplied without touching the code:

```bash
bal run -- -Cport=9000
```

### 3.2 Run the command-line client

In a second terminal:

```bash
cd library-and-resource-management-client
bal run
```

The client presents a numbered menu covering the whole API: the global view,
the campus view, asset look-up and CRUD, loans and returns, room and lab
bookings, the overdue dashboard, the schedule manager, components, work orders
with sub-tasks, and institution management. Point it at another host with
`bal run -- -CapiUrl=http://192.168.1.10:8080/library`.

### 3.3 Browser console (bonus interface)

Open <http://localhost:8080/> once the backend is running. Four tabs mirror the
client: **Catalogue** (filter, register and remove assets), **Loans &
bookings**, **Maintenance** (overdue dashboard, schedule manager, work orders)
and **Institutions**. It is a single static page that calls the same REST API
with `fetch`, so nothing about the backend changes to support it.

### 3.4 Tests

```bash
cd library-and-resource-management-api
bal test
```

Twelve test cases cover the date arithmetic, asset CRUD, unique-key enforcement,
loan and return rules, overlapping room bookings, the work-order lifecycle,
overdue detection and the campus filter.

---

## 4. Question 2 — Rental Accommodation System (gRPC)

### 4.1 Generate the stub — do this first

The Ballerina stub is generated from the contract rather than committed, so it
always matches your distribution:

```bash
./scripts/generate-stubs.sh        # Windows: scripts\generate-stubs.bat
```

This writes `rental_pb.bal` (the message records and the `RentalServiceClient`)
into both `rental-accommodation-server/` and `rental-accommodation-client/`. It is the
equivalent of running, once per package:

```bash
bal grpc --input proto/rental.proto --output rental-accommodation-server
bal grpc --input proto/rental.proto --output rental-accommodation-client
```

### 4.2 Start the server

```bash
cd rental-accommodation-server
bal run
```

It listens on **port 9090** with no data pre-loaded — every Host, Guest, and
property is registered through the client itself. Override the port with
`bal run -- -CgrpcPort=9500`.

### 4.3 Run the client

```bash
cd rental-accommodation-client
bal run
```

The menu drives each RPC on its own with prompted input:

| Option | RPC | Style |
|---|---|---|
| 1 | `create_users` | client-side streaming, one profile — registers a Host |
| 2 | `create_users` | client-side streaming, one profile — registers a Guest |
| 3 | `add_property` | simple |
| 4 | `update_property` | simple |
| 5 | `remove_property` | simple |
| 6 | `create_users` | client-side streaming, many profiles — enter several, then `done` |
| 7 | `list_available_properties` | server-side streaming — matches print as they arrive |
| 8 | `search_property` | simple |
| 9 | `book_property` | simple |
| 10 | `confirm_booking` | simple |
| 11 | `cancel_booking` | simple — bonus RPC beyond the brief's minimum |
| 12 | `rate_property` | simple — bonus RPC beyond the brief's minimum |

Options 1 and 2 are a convenience: registering exactly one person is the
common case, so they collect one profile and send it as a batch of one
through the same client-streaming RPC that option 6 drives with many.

A typical run: option 1 to register a Host, option 2 to register a Guest,
option 3 to list a property under that Host, option 9 to put a stay in the
cart as the Guest, then option 10 to confirm it. Option 9 also demonstrates
rejection — book the same property over an overlapping date range a second
time and it comes back refused rather than double-booked. Option 11 frees
those dates up again by cancelling the confirmed booking, and option 12 lets
a Guest leave a 1-5 rating that shows up as a running average on every
listing (option 7 and option 8 both print it).

---

## 5. REST endpoints at a glance

Base path `http://localhost:8080/library`. Full request and response examples
are in [`docs/api-reference.md`](docs/api-reference.md).

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/assets` | Global view; `?institution=&site=&status=` filters it |
| `POST` | `/assets` | Register an asset |
| `GET` | `/assets/{assetTag}` | Look up one asset |
| `PUT` | `/assets/{assetTag}` | Full replacement (idempotent) |
| `PATCH` | `/assets/{assetTag}` | Partial update |
| `DELETE` | `/assets/{assetTag}` | Remove an asset |
| `GET` | `/institutions/{id}/assets` | Campus view; `?site=` narrows it |
| `POST` | `/assets/{assetTag}/components` | Add a component |
| `DELETE` | `/assets/{assetTag}/components/{compId}` | Remove a component |
| `GET` | `/assets/{assetTag}/schedules` | List schedules and bookings |
| `POST` | `/assets/{assetTag}/schedules` | Add a servicing schedule |
| `DELETE` | `/assets/{assetTag}/schedules/{scheduleId}` | Remove a schedule |
| `POST` | `/assets/{assetTag}/workorders` | Open a work order |
| `PUT` | `/assets/{assetTag}/workorders/{orderId}` | Update or close it |
| `POST` | `/assets/{assetTag}/workorders/{orderId}/tasks` | Add a sub-task |
| `DELETE` | `/assets/{assetTag}/workorders/{orderId}/tasks/{taskId}` | Remove a sub-task |
| `POST` | `/assets/{assetTag}/loan` | Loan an asset out |
| `POST` | `/assets/{assetTag}/return` | Return a loaned asset |
| `POST` | `/assets/{assetTag}/bookings` | Book a lab or meeting room |
| `GET` | `/maintenance/overdue` | Elapsed maintenance and servicing schedules |
| `GET` | `/loans/overdue` | Loans past their due date |
| `GET` | `/institutions` | List registered institutions |
| `POST` | `/institutions` | Register an institution |
| `POST` | `/institutions/{id}/sites` | Add a campus to an institution |
| `DELETE` | `/institutions/{id}` | Remove an institution from the listing |
| `GET` | `/health` | Liveness probe |

Errors always come back in the same envelope, so the clients can render them
uniformly:

```json
{ "code": "CONFLICT",
  "message": "An asset with tag 'NUST-LIB-3DP-001' already exists",
  "resource": "NUST-LIB-3DP-001" }
```

`400` validation failed · `404` not found · `409` conflict · `500` unexpected.

---

## 6. Where each requirement is implemented

**Question 1**

| Requirement | Implementation |
|---|---|
| Create, update, look up, remove resources | `service.bal` — `POST/PUT/PATCH/GET/DELETE /assets…`; logic in `store.bal` |
| View all assets | `GET /assets` → `listAssets()` |
| View by institution and site | `GET /assets?institution=&site=`, `GET /institutions/{id}/assets` → `filterAssets()` |
| Item status and booking schedules | `?status=` filter, `/schedules`, `/bookings` with overlap checking |
| Manage institutions | `/institutions` backed by `table<Institution> key(institutionId)` |
| Manage schedules | `POST`/`DELETE /assets/{tag}/schedules` |
| Error and wrong-call handling | `toApiError()`, typed store errors, uniform `ErrorResponse` |
| Database integration | `map<Asset>` keyed on `assetTag` + institution `table` (`store.bal`) |
| Client implementation | `library-and-resource-management-client` |
| Web interface (bonus) | `library-and-resource-management-api/resources/index.html` |

**Question 2**

| Requirement | Implementation |
|---|---|
| Protocol Buffer definition | `proto/rental.proto` — 10 RPCs (8 required by the brief + 2 bonus), 1 client stream, 1 server stream |
| Server implementation | `rental-accommodation-server/rental_service.bal` + `store.bal` |
| Concurrency and state | `isolated` maps guarded by `lock` in `store.bal` |
| Validation and pricing | date checks, overlap detection, nights × rate in `confirm_booking` |
| `remove_property` response | returns the Host's remaining *available* listings in that same region, per the brief |
| Bonus: `cancel_booking` | completes the booking lifecycle (book → confirm → cancel), freeing a confirmed stay's dates |
| Bonus: `rate_property` | 1-5 rating with an optional review; `Property` carries a running `average_rating`/`rating_count` |
| Client implementation | `rental-accommodation-client/main.bal`, including both streaming styles |

---

## 7. Troubleshooting

| Symptom | Fix |
|---|---|
| `undefined symbol 'RentalServiceClient'` | The stub has not been generated — run `./scripts/generate-stubs.sh` |
| Q2 fails on the descriptor annotation | Older distributions emit `@grpc:ServiceDescriptor` instead of `@grpc:Descriptor`; copy the annotation line from `bal grpc --mode service` output into `rental_service.bal` |
| `UI_UNAVAILABLE` in the browser | The backend was started from the wrong directory — run `bal run` inside `library-and-resource-management-api` |
| `Address already in use` | Another process holds 8080 or 9090; pass `-Cport=` or `-CgrpcPort=` |
| Client cannot reach the API | Start the backend first, or point the client at the right host with `-CapiUrl=` |
