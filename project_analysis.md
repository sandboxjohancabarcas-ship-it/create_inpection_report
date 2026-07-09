# WartungsTool — Full Project Analysis
> **Last updated:** 2026-06-29 — All pages read, owner decisions recorded.

## 1. What is the App?

**WartungsTool** is a professional Flutter application for **door maintenance inspections** (Türwartung) used in the German building services/facility management sector. It bridges field data collection (Android tablet/phone) with office management and standardized GAEB reporting (Windows desktop).

The app follows a **"Door-as-Patient" philosophy**: every physical door has a permanent, immutable identifier (the `doorAlias` / `doorNumber`) that persists across all inspections and lifecycle events — analogous to a patient's medical record number.

---

## 2. Technical Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (Dart) — cross-platform (Android + Windows) |
| Local DB (Android/Inspector) | `sqflite` → `working.db` |
| Local DB (Windows/Manager) | `sqflite_common_ffi` → `door_inspection.db` |
| State Management | Stateful Widgets (no Bloc/Riverpod) |
| Data Exchange | File-based sync (shared folder `.db` files) + KINCHI API (Strapi/Keycloak) |
| Cloud Integration | KINCHI Process API: OIDC/Keycloak auth, Strapi v4 file uploads |
| Export Formats | GAEB 90 (`.d83`) and GAEB DA XML 3.2 (`.x83`) |
| Dependencies | `sqflite`, `sqflite_common_ffi`, `path`, `path_provider`, `intl`, `cupertino_icons` |

---

## 3. Data Model (Database Schema)

### 5 Core Tables (identical schema in both DBs, except `syncStatus` column only in `working.db`)

```
doors
  id INTEGER PK, pos, doorNumber, floor, roomNumber, roomDesignation,
  doorType, wingCount, material, manufacturer, dinConfiguration,
  closerType, closingSequenceSystem, lockDimensions,
  closerOnHingeSide BOOL, closerOnOppositeSide BOOL, lintelHeightUnder1m BOOL,
  escapeDoorControl BOOL, accessControl TEXT,
  escapeRouteSituation BOOL, escapeRouteSignage BOOL,
  blindCylinder BOOL, pzCylinder BOOL, fittingType, panicFunction,
  escapeDirectionRespected BOOL, fullPanicStandWing BOOL, doorFunctionOK BOOL
  [syncStatus TEXT] ← only in working.db

inspections
  inspectionId INTEGER PK AUTOINCREMENT,
  clientName, objectAddress, date TEXT (ISO), contactPerson,
  inspectorName, auftragsnummer (Job Number / unique ID of the assignment)
  [syncStatus TEXT]

inspection_doors  ← JUNCTION TABLE (door × inspection state)
  id INTEGER PK AUTOINCREMENT,
  inspectionId FK, doorId FK,
  status TEXT ('InProgress' | 'Passed' | 'Failed'),
  notes TEXT, attachments TEXT (comma-separated paths)
  [syncStatus TEXT]

error_catalog  ← master list of standardized defects
  errorId INTEGER PK AUTOINCREMENT, code TEXT UNIQUE, description,
  category, severity ('low'|'medium'|'high'|'critical'),
  recommendation TEXT, normReference TEXT,
  status TEXT ('Approved'|'Pending'|'Rejected'),
  requestedBy TEXT, requestDate TEXT, sourceInspectionDoorId INTEGER
  [syncStatus TEXT]

inspection_door_errors  ← specific defect instances per door per inspection
  id PK AUTOINCREMENT,
  inspectionDoorId FK → inspection_doors.id,
  errorId FK → error_catalog.errorId (nullable: null = provisional pending error)
  quantity INTEGER, severity TEXT, notes TEXT,
  resolutionStatus TEXT ('Open'|'In Progress'|'Resolved')
  [syncStatus TEXT]
```

### Key Indices
- `doors.doorNumber`
- `inspections.clientName`, `auftragsnummer`, `date`
- `error_catalog.description`
- `doors.doorNumber` (local DB)

---

## 4. User Roles & Workflows

### A. Manager (Windows Desktop) — "Source of Truth"
Operates against `door_inspection.db` (master DB).

**Workflow:**
1. Sets up jobs (Inspections) and assigns doors to them
2. Manages the Error Catalog (add, edit, delete, bulk import, approve proposals)
3. Exports "Job Packages" to the shared folder for inspectors
4. Merges finished `working.db` files from the field
5. Generates GAEB `.d83` / `.x83` reports for downstream systems
6. Uploads GAEB files to the KINCHI cloud (Strapi/Keycloak)
7. Reviews and approves/rejects new error proposals from inspectors

### B. Inspector (Android Tablet/Phone) — "Field Worker"
Operates against `working.db` (local, isolated DB).

**Workflow:**
1. Downloads a job package from the Manager's Main DB (`JobSelectionPage`)
2. Walks the building, visits each door
3. Opens each door in the list, fills in technical specifications
4. Records defects from the Error Catalog, or proposes new ones (Pending)
5. Uploads (syncs) finished `working.db` back to the Main DB
6. Local data is cleared after sync

---

## 5. UI Architecture & Page Map

```
MainNavigationPage (BottomNavigationBar)
│
├── Tab 0: DoorListPage (Inspector view - works on working.db)
│   ├── AppBar: Search, cloud_upload (sync to Main DB), cloud_download (fetch job)
│   ├── ListView: Doors with swipe-to-delete & tap-to-edit
│   ├── FAB: Add new door
│   │
│   ├── → DoorInspectionForm (new_door_page.dart) — Create/Edit door
│   │   ├── Section: Inspektionsdaten (customer, job number, date, inspector)
│   │   ├── Section: Grundinformationen (door number, floor, room)
│   │   ├── Section: Türspezifikationen (type, wing count, material, manufacturer, DIN, closer, lock)
│   │   ├── Section: Installation (hinge side, opposite side, lintel height)
│   │   ├── Section: Sicherheit & Zugang (access control, escape route, signage, cylinder, panic)
│   │   ├── Section: Bewertung (doorFunctionOK)
│   │   └── Buttons: [Speichern] → [Fehler verwalten →]
│   │
│   │   └── → ErrorManagementPage (error_management_page.dart)
│   │       ├── Lists all errors recorded for the specific door in the current inspection
│   │       ├── FAB: Add error (from catalog search or provisional new entry)
│   │       └── Dialog options: select from catalog OR create provisional (Pending) entry
│   │
│   └── → JobSelectionPage (job_selection_page.dart) — Download job from Main DB
│       ├── Search bar: search inspections by client, job number, date
│       ├── ListView: Available inspections with checkboxes for multi-select
│       ├── Tap single → triggers downloadJobData() immediately
│       └── Bottom bar (if multi-selected): [GAEB 90 export] | [GAEB XML export]
│
└── Tab 1: ManagerDashboard (manager_dashboard.dart) — Manager view
    ├── AppBar: refresh, re-seed catalog
    ├── Search bar + category filter chips
    ├── Stats card: Total, Pending, Critical, High, Medium
    ├── ListView: Error catalog (code, description, category chip, severity chip)
    ├── Each item: popup menu → Edit / Delete
    │
    ├── FAB stack:
    │   ├── [Anfragen prüfen] → ErrorConsolidationPage
    │   ├── [Massen-Import] → BulkErrorImportPage
    │   └── [+] → inline add error dialog
    │
    ├── → ErrorConsolidationPage (error_consolidation_page.dart)
    │   ├── Lists all 'Pending' error proposals from field inspectors
    │   └── Each: [Ablehnen] | [Prüfen & Bearbeiten] | [Direkt genehmigen]
    │
    └── → BulkErrorImportPage (bulk_error_import_page.dart)
        ├── Import modes: Text, File, Excel/CSV
        └── → ConflictReviewPage (conflict_review_page.dart)
```

---

## 6. Service Layer

### `DatabaseService` (Master DB — `door_inspection.db`)
- DB version: **10** (schema evolution tracked via migrations)
- CRUD: `insertDoor`, `getAllDoors`, `updateDoor`, `deleteDoor`
- CRUD: `insertInspection`, `searchInspections` (LIKE query, max 50)
- CRUD: `insertInspectionDoor`, `getInspectionDoorsByInspectionId`
- CRUD: `insertInspectionDoorError`, `getErrorsForInspectionDoor`
- Error Catalog: `getAllErrorCatalog(status?)`, `insertErrorCatalog`, `searchErrorCatalog`, `deleteErrorCatalog`
- **Merge logic**: `mergeErrorCatalog()` with conflict detection (same code / same description)
- **Conflict resolution**: `applyConflictResolutions()` — keepExisting / replaceExisting / addAsNew / skip
- Supports seeding from `DoorErrorCatalog.getStandardErrors()` as fallback

### `LocalDatabaseService` (Working DB — `working.db`)
- DB version: **3**
- All same CRUD operations but with `syncStatus` field tracking
- `syncToMainDatabase()`: pushes all `pending` records to main DB (catalog → inspections → doors → junctions → errors)
- `downloadJobData()`: clears local DB, then copies job-specific records from Main DB
- `clearSyncedData()`: deletes doors/inspections/inspection_doors/inspection_door_errors (catalog preserved)
- `proposeNewError()`: creates a Pending catalog entry + links a door error instance
- `refreshLocalCatalogFromMain()`: syncs approved errors from main DB to local
- Smart search: `searchDoors()` via LEFT JOIN across junctions and error catalog

### `GaebExportService`
- `exportToGaeb90()`: generates GAEB 90 `.d83` fixed-width format (ZA00, ZA01, ZA21, ZA25, ZA26, ZA99 records)
- `exportToGaebXml()`: generates GAEB DA XML 3.2 `.x83` format
  - XML structure: `GAEB > Award > BoQ > BoQBody > BoQCtgy (per job) > ItemList > Item (per door)`
  - HTML-compliant XHTML in `<DetailTxt>` blocks
  - Door number used as `RNoPart` identifier
  - XML special character escaping

---

## 7. Current State & Known Issues

### What Works
- ✅ Full Inspector workflow: download job → fill in doors → record errors → sync back
- ✅ Full Manager workflow: manage error catalog, view pending proposals, approve/reject
- ✅ Bulk import of errors (text, file, CSV/Excel)
- ✅ Conflict detection and resolution during bulk import
- ✅ GAEB export: both `.d83` and `.x83` formats (validator-compliant)
- ✅ Multi-job selection & GAEB export
- ✅ Swipe-to-delete and list management for doors
- ✅ Search across doors (by number, error code, error description via JOIN)
- ✅ Search across inspections (client name, job number, date)
- ✅ Category filter chips in Manager Dashboard
- ✅ Sync status tracking (`pending` / `synced`) for field-to-office data flow

### Known To-Do / Open Issues (from PROJECT_CONTEXT.md)
- ❌ **Authentication**: No login system yet — no user identity
- ❌ **Role Separation**: Both Manager and Inspector modes live in the same app — no platform-conditional routing (`kIsWeb`, `Platform.isAndroid`, `Platform.isWindows`)
- ❌ **Safety Warning**: No confirmation prompt before `downloadJobPackage` overwrites unsaved local data
- ❌ **File Naming Convention**: `.db` exchange files not named systematically (e.g., `Job_Date_Inspector.db`)
- ❌ **Photo Documentation**: `attachments` field exists in schema but no photo capture/link UI
- ❌ **Validation**: No DIN/EN strict validation rules for technical door fields
- ❌ **GAEB Mapping**: Error codes and door attributes need richer mapping to GAEB BoQ hierarchy
- ❌ **Migration Module**: Phase 1 initiated (Excel-based door/historical error import) but not complete
- ❌ **Door Alias**: The `doorAlias` field referenced in PROJECT_CONTEXT as the "Patient ID" is **not yet in the `Door` model** — the current code uses `doorNumber` as the identifier. This is a significant gap.

### Architecture Concerns
- `main.dart` initializes both DBs unconditionally — no platform/role detection yet
- `DoorInspectionForm` (new_door_page.dart) still contains inspection metadata fields (customer, job number) even though the data model separates these into `inspections` table — it's a UX inconsistency
- `database_service.dart` still calls `DoorErrorCatalog.getStandardErrors()` as seed fallback, but PROJECT_CONTEXT says this static data was meant to be removed in favor of CSV-based import
- `searchResults` state variable in `ErrorManagementPage` is class-level but modified inside a dialog's `StatefulBuilder` — can lead to stale state bugs
- DB version 10 in main DB but version 3 in local DB — not inherently a problem but requires careful synchronization during schema evolution
- `conflict_review_page.dart` exists but was not fully read — needs exploration

---

## 8. `ConflictReviewPage` — Complete Analysis

File: [conflict_review_page.dart](file:///c:/Users/Cabarcas/WartungTool/create_inpection_report-1/lib/pages/conflict_review_page.dart)

This page is navigated to from `BulkErrorImportPage` (both automatically during import if conflicts are detected, and manually via the "Lösen" button on the conflicts card). It receives a `List<ImportConflict>` as a constructor argument.

**What it does:**
- Displays each conflict as a side-by-side card: **"Aktuell in Katalog"** (existing, blue) vs. **"Neu importiert"** (incoming, green)
- Shows the conflict reason (same code different data / same description different code)
- Lets the Manager choose a resolution per conflict via `RadioListTile`:
  - **keepExisting** — skip incoming, keep DB as-is (default)
  - **replaceExisting** — overwrite DB entry with incoming data
  - **addAsNew** — save incoming under a new code (shows a text field for the new code)
  - **skip** — leave both untouched
- Validates that if `addAsNew` is chosen, a non-empty new code is provided
- On confirm, calls `DatabaseService.applyConflictResolutions()` which executes the decisions inside a single DB transaction
- Returns `true` to the caller on success

**`BulkErrorImportPage` — Complete Analysis:**
- Import pipeline: Text area (pipe-delimited format `Code|Desc|Category|Severity|Recommendation|Norm`) → parse lines → call `DatabaseService.mergeErrorCatalog()` → show Phase 1 results → navigate to `ConflictReviewPage` if conflicts
- Import modes: "Text-Import" (focus textarea), "Datei-Import" (reads from clipboard — ⚠️ not a real file picker yet), "Excel/CSV" (delegates to file import = clipboard), "Katalog leeren" (full clear with confirmation)
- Severity normalization supports German (`niedrig/mittel/hoch/kritisch`) and numeric (`1/2/3/4`) aliases
- Shows Import-Protokoll (log of OK / FEHLER lines) and conflict summary card
- Conflict card shows a preview list and a "Lösen" button that navigates to `ConflictReviewPage`

> [!WARNING]
> `_importFromFile()` and `_importFromExcel()` currently use **clipboard paste**, not a native file picker. No `file_picker` package is in `pubspec.yaml`. This is a known limitation for a future improvement.

---

## 9. Decisions & Answers from Owner (2026-06-29)

| Question | Decision |
|---|---|
| **Role/Platform separation** | App intentionally **joined for testing**. Future: separate by platform. Need a practical dual-platform testing strategy. |
| **`doorAlias` / Patient ID** | **Add to data model now.** Strategy documented below (§10). |
| **Authentication** | **PIN login** — sufficient for now. Full Keycloak auth is future. |
| **Inspector new door on-site** | **Queue for Manager review** — merge does NOT auto-create. Manager must approve. |
| **Photo documentation** | **Gallery pick (file attachment)** — planned for future. Camera capture is also future. |
| **`conflict_review_page.dart`** | Now fully analyzed — see §8 above. |

---

## 10. `doorAlias` Migration Strategy

The `doorAlias` ("Patient ID") is the **permanent, immutable identifier** for a door's entire lifecycle. It must be distinct from `doorNumber` (which is a human-readable label that could theoretically change).

### Why it's needed
- GAEB exports currently use `doorNumber` stripped of non-numeric chars as the item identifier → fragile
- Cross-inspection history tracking relies on a stable ID
- The `BoQCtgy ID` and `Item ID` in `.x83` exports should be based on `doorAlias`

### Proposed Migration Steps

**Step 1 — Add field to `Door` model** (`door.dart`)
```dart
final String doorAlias; // The permanent, immutable "Patient ID"
```
Add to constructor, `copyWith`, `toMap`, `fromMap`.

**Step 2 — Migrate both databases** (DB version bump)
- `door_inspection.db`: bump to version **11**, add `ALTER TABLE doors ADD COLUMN doorAlias TEXT`
- `working.db`: bump to version **4**, same migration
- On migration, auto-populate existing rows: `UPDATE doors SET doorAlias = doorNumber WHERE doorAlias IS NULL`

**Step 3 — Generation rule for new doors**
- When a new door is created in `DoorInspectionForm`, auto-generate `doorAlias` as: `{timestamp}-{doorNumber}` or a UUID, then make it read-only in the UI
- Manager can manually set it during initial import

**Step 4 — Update GAEB export** (`gaeb_export_service.dart`)
- Replace `door['doorNumber']` with `door['doorAlias']` as the primary identifier in `RNoPart`, `BoQCtgy ID`, and `Item ID`

**Step 5 — Update search indices**
- Add: `CREATE INDEX IF NOT EXISTS idx_doors_alias ON doors (doorAlias)`

**Step 6 — Update `downloadJobData` / sync**
- Ensure `doorAlias` is included in the sync tables list (already will be since it's part of `doors.*`)

### Open sub-questions before implementation
1. Should `doorAlias` be user-editable by the Manager (after initial creation), or truly immutable once set?
2. Should `doorAlias` be globally unique across the entire system, or just unique per client?
3. What format? Free text, numeric sequence, or UUID?

---

## 11. Dual-Platform Testing Strategy

Since the app is intentionally joined (both tabs visible on any platform) during development, here are practical approaches for the future:

### Option A — Runtime `Platform` flag (Recommended short-term)
```dart
import 'dart:io';
final bool isManagerMode = Platform.isWindows;
final bool isInspectorMode = Platform.isAndroid;
```
- Show/hide tabs based on flag
- No impact on shared code
- During development: use a **debug toggle in settings** to override the platform flag

### Option B — Build flavors (Future)
- `manager` flavor: Windows-only build, always Manager UI
- `inspector` flavor: Android-only build, always Inspector UI
- Allows separate app store listings

### For Testing Both Simultaneously
- Run the **Windows build** as Manager (opens `door_inspection.db`)
- Run the **Android emulator** as Inspector (opens `working.db`)
- Both can share a common folder on the dev machine for `.db` file exchange testing
- Or use the KINCHI API as the exchange point if it's available in a dev environment.

+++++++RESPONSE++++++++
Step 3 — Generation rule for new doors: No, the string for alias is Customer-AddressObject-DoorNumber. it should be shortened so that still meaningful. Here the philosohpy of Door//Patient can be used. The idea also is that it with the alias can be located the door easily. Step 5 — Update search indices investigate because there can be already an approach for it. Open sub-questions before implementation: 1. editable by manager.2. globally along entire system.3. already provided in step 3 in this text. Max 12 char,.
