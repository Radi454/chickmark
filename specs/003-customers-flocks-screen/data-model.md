# Data Model: Phase 2 — Customers & Flocks Screen

**Branch**: `003-customers-flocks-screen` | **Date**: 2026-04-18

## Entities

---

### Customer

**Table**: `customers` (already exists in `DatabaseHelper._onCreate`)

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | TEXT PK | No | UUID generated client-side |
| `name` | TEXT | No | Full customer name (required) |
| `location` | TEXT | Yes | Optional |
| `phone` | TEXT | Yes | Optional |
| `email` | TEXT | Yes | Optional |
| `createdAt` | TEXT | No | ISO 8601 timestamp |
| `createdBy` | TEXT | No | User ID of creator |

**Dart model**: `lib/data/models/customer_model.dart` — no changes needed.

**Repository**: `lib/data/repositories/customer_repository.dart`
- `insertCustomer(CustomerModel)` — used on Save
- `getAllCustomers()` — used on tab load
- `updateCustomer(CustomerModel)` — used on Edit (future)

---

### Flock

**Table**: `flocks` (already exists in `DatabaseHelper._onCreate`)

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | TEXT PK | No | UUID generated client-side |
| `customerId` | TEXT FK | No | References `customers.id` |
| `flockId` | TEXT | No | Free-text label (e.g. "FL-001") |
| `breed` | TEXT | No | One of: Ross308, Arbo, Avian, Cobb500, Hubbard, IR |
| `entryDate` | TEXT | No | ISO 8601 date |

**Dart model**: `lib/data/models/flock_model.dart` — no changes needed.
- Computed getter `currentAgeWeeks` → `HatchDateUtils.flockAgeWeeks(entryDate)` already present.

**Repository**: `lib/data/repositories/flock_repository.dart`
- `insertFlock(FlockModel)` — used on Add Flock save
- `getFlocksByCustomer(String customerId)` — used on Customer Detail load

---

### Audit *(read-only reference in this feature)*

**Table**: `audits` (already exists — large denormalized schema)

**Fields surfaced in Audit History cards**:

| Field | Column | Notes |
|-------|--------|-------|
| Age badge | derived from `flockId` → flock's `entryDate` | Display `flockAgeWeeks` at time of audit |
| Customer | `customerId` | Resolved to name via `CustomerRepository` |
| Flock | `flockId` | Display raw `flockId` text |
| Date | `date` | Formatted display |
| Audit type | `auditType` | One of 5 types |
| Setter ID | `setterId` | Raw text |
| Hatcher ID | `hatcherId` | Raw text |
| Status | `status` | Badge: draft / complete |

**Repository**: `lib/data/repositories/audit_repository.dart`
- `getAuditsByCustomer(String customerId)` — used for Audit History section

---

## Derived / Computed Values

| Value | Formula | Where calculated |
|-------|---------|-----------------|
| `currentAgeWeeks` | `floor((today − entryDate).inDays / 7)` | `FlockModel.currentAgeWeeks` getter → `HatchDateUtils.flockAgeWeeks()` |
| `flockCount` per customer | `count of flocks WHERE customerId = customer.id` | `CustomersProvider` — loaded once on tab entry |
| Age badge on audit card | `HatchDateUtils.flockAgeWeeks(flock.entryDate)` using **audit's date** as reference | `CustomersProvider` or widget |

---

## State (CustomersProvider)

```
CustomersProvider
├── List<CustomerModel> _allCustomers        // loaded from SQLite on tab open
├── Map<String, int> _flockCounts           // customerId → count
├── String _searchQuery                      // drives filteredCustomers
├── CustomerModel? _selectedCustomer        // set on card tap
├── List<FlockModel> _flocks               // flocks for selected customer
├── FlockModel? _selectedFlock             // drives flock detail card
├── List<AuditModel> _audits              // audits for selected customer
└── bool _isLoading

Derived:
└── List<CustomerModel> filteredCustomers   // _allCustomers filtered by _searchQuery
```

---

## Validation Rules

| Rule | Entity | Condition |
|------|--------|-----------|
| Name required | Customer | `name.trim().isNotEmpty` |
| Entry date required | Flock | Date picker always returns a value; default = today |
| Breed required | Flock | Dropdown always has a selected value; default = `'Ross308'` |
| Flock ID required | Flock | `flockId.trim().isNotEmpty` |
| Age ≥ 0 | Flock display | `max(0, flockAgeWeeks)` — handled in widget |

---

## No Schema Migrations Required

Both `customers` and `flocks` tables are already defined in `DatabaseHelper._onCreate` (version 1). No DDL changes are needed for this feature.
