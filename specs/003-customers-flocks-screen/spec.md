# Feature Specification: Phase 2 — Customers & Flocks Screen

**Feature Branch**: `003-customers-flocks-screen`
**Created**: 2026-04-18
**Status**: Draft

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Browse & Search Customers (Priority: P1)

An auditor opens the Customers tab and sees all customers in a scrollable list. They can type in a search bar to filter customers by name in real time. Each card displays the customer's name, location, phone number, and a badge showing how many flocks they have registered.

**Why this priority**: This is the entry point to the entire customer-management flow. Without a working list view, no downstream actions (adding customers, viewing flocks, viewing audits) are accessible.

**Independent Test**: Can be tested by launching the Customers tab with pre-seeded data and verifying cards render correctly and search filters results.

**Acceptance Scenarios**:

1. **Given** the app is open and customers exist, **When** the user navigates to the Customers tab, **Then** all customers are displayed as cards sorted alphabetically, each showing name (bold), location, phone, and flock count badge.
2. **Given** the Customers list is visible, **When** the user types in the search bar, **Then** the list filters in real time to show only customers whose names contain the typed text (case-insensitive).
3. **Given** the search bar has text, **When** the user clears the text, **Then** the full customer list is restored.
4. **Given** no customers exist, **When** the user views the tab, **Then** an empty state message is shown.

---

### User Story 2 - Add a New Customer (Priority: P1)

An auditor taps [+ Add Customer] to open a bottom sheet form. They enter at minimum a full name (required) and optionally a location, phone, and email. Tapping Save creates the customer and closes the sheet.

**Why this priority**: Customer creation is a prerequisite for all audit workflows; without customers, flocks and audits cannot be associated.

**Independent Test**: Can be tested by tapping Add Customer, filling the form, saving, and verifying the new card appears in the list.

**Acceptance Scenarios**:

1. **Given** the bottom sheet is open, **When** the user submits with no name entered, **Then** a validation error is shown and the form is not submitted.
2. **Given** a valid name is entered with optional fields empty, **When** Save is tapped, **Then** the customer is created, the sheet closes, and the new customer card appears in the list immediately.
3. **Given** all fields are filled, **When** Save is tapped, **Then** all provided data (name, location, phone, email) is saved and reflected on the customer card.
4. **Given** the bottom sheet is open, **When** the user dismisses it without saving, **Then** no customer is created and no data is lost.

---

### User Story 3 - View Customer Detail & Manage Flocks (Priority: P2)

An auditor taps a customer card to open the Customer Detail screen. They can see the customer's name in the header, manage flocks via a dropdown and Add Flock button, and view the selected flock's details including Flock ID, breed, entry date, and auto-calculated current age in weeks.

**Why this priority**: Flock management is required before audits can reference a specific flock; however, viewing existing customers is still possible at P1.

**Independent Test**: Can be tested by opening a customer, adding a flock with an entry date, and verifying the age is calculated correctly.

**Acceptance Scenarios**:

1. **Given** a customer is selected, **When** the detail screen opens, **Then** the customer name is displayed in the header with an Edit button visible in the top right.
2. **Given** the Flocks section is visible, **When** the user taps [+ Add Flock], **Then** a form appears to enter Flock ID, select a breed from the dropdown (Ross308, Arbo, Avian, Cobb500, Hubbard, IR), and pick an entry date.
3. **Given** a flock with an entry date is saved, **When** the flock card is shown, **Then** the Current Age field displays `floor((today − entry_date).inDays / 7)` weeks and is read-only.
4. **Given** multiple flocks exist for a customer, **When** the user selects a flock from the dropdown, **Then** the selected flock's details update in the card below.
5. **Given** no flocks exist for the customer, **When** the Flocks section is shown, **Then** only the [+ Add Flock] button is visible.

---

### User Story 4 - View Audit History for a Customer (Priority: P3)

Below the Flocks section on the Customer Detail screen, an auditor sees a chronological list (newest first) of all audits linked to that customer. Each audit card shows the age badge, customer name, flock, date, audit type, setter/hatcher IDs, and a status badge. Tapping an audit opens a read-only view of its details.

**Why this priority**: Audit history provides context for decisions but is not required to create or manage customers or flocks.

**Independent Test**: Can be tested by navigating to a customer with existing audit records and verifying the list order and card content.

**Acceptance Scenarios**:

1. **Given** audits exist for a customer, **When** the Audit History section is visible, **Then** audits are listed newest to oldest with correct card fields (age badge, customer, flock, date, type, setter/hatcher ID, status badge).
2. **Given** an audit card is tapped, **When** the detail view opens, **Then** all audit fields are displayed in read-only mode with no edit controls.
3. **Given** no audits exist for the customer, **When** the Audit History section is shown, **Then** an empty state message is displayed.

---

### Edge Cases

- What happens when a customer's name already exists? — Duplicate names are allowed (no uniqueness constraint); the auditor is responsible for distinguishing entries.
- What happens if entry date is set to a future date? — Current age calculation returns a negative value; the UI displays 0 weeks as a floor.
- What happens when the flock dropdown has many entries? — The dropdown is scrollable with no hard cap on flock count.
- How does the system handle a lost connection while saving? — Data is persisted locally first; Supabase sync retries silently in the background; the user sees no blocking error.
- What happens when a customer has no location or phone? — Those fields are omitted or shown as empty on the card without placeholder dashes.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display all customers in a scrollable list on the Customers tab, each card showing name (bold), location, phone, and flock count badge.
- **FR-002**: System MUST provide a real-time, case-insensitive search bar that filters the customer list by name as the user types.
- **FR-003**: System MUST provide a [+ Add Customer] control that opens a bottom sheet form with fields: Full Name (required), Location, Phone, Email (all optional except name).
- **FR-004**: System MUST validate that Full Name is non-empty before saving a customer; all other fields are optional.
- **FR-005**: System MUST save a new customer immediately to local storage upon tapping Save and close the bottom sheet.
- **FR-006**: System MUST display the Customer Detail screen when a customer card is tapped, showing the customer name as the screen header and an Edit button in the top-right corner.
- **FR-007**: System MUST display a Flocks section on the Customer Detail screen with a dropdown to select an existing flock and a [+ Add Flock] button.
- **FR-008**: System MUST allow adding a flock by specifying: Flock ID (text), Breed (dropdown: Ross308, Arbo, Avian, Cobb500, Hubbard, IR), and Entry Date (date picker).
- **FR-009**: System MUST auto-calculate and display Current Age in weeks as `floor((today − entry_date).inDays / 7)`; this field is read-only and never manually entered.
- **FR-010**: System MUST display a minimum age of 0 weeks when the calculated value is negative (future entry date).
- **FR-011**: System MUST display an Audit History section below the Flocks section, listing all audits for the customer ordered newest to oldest.
- **FR-012**: Each audit card in the Audit History MUST show: age badge, customer name, flock identifier, date, audit type, setter ID, hatcher ID, and status badge.
- **FR-013**: Tapping an audit card MUST open a read-only detail view of that audit with no edit controls.
- **FR-014**: System MUST sync customer and flock data to the remote backend in the background without blocking the user interface.

### Key Entities

- **Customer**: Represents a hatchery client. Attributes: unique ID, full name, location, phone, email, creation timestamp, created-by user.
- **Flock**: Represents a group of birds managed for a customer. Attributes: unique ID, customer reference, flock identifier, breed (enum), entry date. Derived: current age in weeks (calculated at display time).
- **Audit** *(read reference only in this feature)*: Represents a completed hatchery audit linked to a customer and flock. Attributes relevant here: customer reference, flock reference, date, audit type, setter ID, hatcher ID, status.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can add a new customer in under 60 seconds from tapping [+ Add Customer] to seeing the card in the list.
- **SC-002**: The customer list filters visibly within 300 ms of each keystroke in the search bar, regardless of list size up to 500 customers.
- **SC-003**: Current flock age is always accurate to within ±1 day when the device date is correct, with no manual input required.
- **SC-004**: 100% of customer and flock records created while offline are successfully synced to the backend upon next connectivity restoration.
- **SC-005**: Audit history loads and displays for a customer with up to 200 audit records without perceptible delay (under 1 second).
- **SC-006**: All required field validations prevent form submission 100% of the time when the Full Name is blank.

## Assumptions

- The app already has an authenticated user session; no login flow is part of this feature.
- Editing an existing customer (via the Edit button) is out of scope for this phase; the button is visible but wires up in a future phase.
- Deleting customers or flocks is out of scope for this phase.
- The Audit History section is read-only; audit creation happens elsewhere in the app.
- Flock ID is a free-text label chosen by the auditor (e.g., "FL-001"), not auto-generated.
- Age calculation uses the device's local date; no server-side date synchronisation is required.
- Background Supabase sync failures are silent — the user is not shown an error if sync fails; local data remains the source of truth.
- The CustomerRepository and FlockRepository implementations already exist or will be provided by the implementing developer using the established local-first data pattern in this codebase.
