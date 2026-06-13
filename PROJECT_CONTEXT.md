# Project Context: WartungsTool

## 1. Project Overview
**WartungsTool** is a specialized Flutter solution for door maintenance. It bridges field data collection on Android with office management and GAEB-compliant reporting on Windows.

## 2. Technical Stack
- **Framework:** Flutter (Android for Inspectors, Windows for Managers).
- **Database:** SQLite.
    - `sqflite` for Android field devices.
    - `sqflite_common_ffi` for the Windows Manager machine.
- **Data Exchange:** Shared folder file-based sync (No API/Cloud backend).
- **Data Exchange:** Hybrid Approach.
    - Legacy: Shared folder file-based sync for `.db` files.
    - Cloud: KINCHI Process API (Strapi/Keycloak) for document management and GAEB report synchronization.

## 3. Data Model
- **Door:** Master technical data. **Door Alias** acts as a unique **"Patient ID"**—it is the permanent, immutable identifier for the door's lifecycle and historical events.
- **Inspection:** A specific assignment or "Auftrag" identified by a unique **Job Number (Auftragsnummer)**.
- **InspectionDoor:** Junction record representing the "State" of a specific door during a specific inspection (Passed/Failed/Notes).
- **ErrorCatalog:** Standardized list of defects.
- **InspectionDoorError:** Specific instances of catalog errors assigned to a door during a site visit.

## 4. User Roles & Data Flow

### A. Manager (Windows Machine) - "The Source of Truth"
- **Control:** Full access to Master DB.
- **Workflow:** 
    1. Creates/Imports the Error Catalog.
    2. Sets up Jobs (Inspections) and assigns Doors.
    3. Exports "Job Packages" to a shared folder.
    4. Merges finished `working.db` files from inspectors.
    5. Generates GAEB exports (.d83, .x83 v3.3).

### B. Inspector (Android Tablet/Phone)
- **Control:** Limited to the `working.db`.
- **Workflow:**
    1. Imports Job Package (purges existing local data).
    2. Site visits: Edits doors, records errors, creates new error requests.
    3. Exports results to the shared folder.

### C. API Integration (New)
- **Authentication:** OIDC via Keycloak (`password` grant).
- **Media Management:** Physical file uploads to Strapi Media Library.
- **Document Records:** Linking uploaded GAEB files to specific Project Directories.
- **Orchestrated Purge:** Ability to delete both the database record and the physical storage in one transaction.

### C. Tables involved in Sync
- **To Inspector:** `inspections`, `doors`, `inspection_doors`, `error_catalog`.
- **To Manager:** `inspection_doors`, `inspection_door_errors`, `error_catalog` (Pending requests).

## 5. Key Business Logic
- **Merge Strategy:** Master DB is the authority. Overwrites occur based on matching **Auftragsnummer**.
- **Error Approval:** New field requests are 'Pending' until approved by an Admin.
- **Standardization:** Automatic string normalization (e.g., "L" -> "DIN L").
- **Atomicity:** One inspector per specific door per job to prevent data collisions.

## 6. UI Implementation Status
- **Inspector:** `DoorList`, `DoorDetail`, `ErrorManagement`.
- **Manager:** `JobSelection` (GAEB Export), Error Approval.
- **Role Separation:** (Priority) Logic needed to distinguish between Windows (Manager) and Android (Inspector) modes.

## 7. Known To-Do List & Roadmap
- [ ] **Safety Warning:** Warn inspector before `downloadJobPackage` if local data is unsaved.
- [ ] **Authentication:** Login system is planned but not yet implemented.
- [ ] **File Naming:** Implement a naming convention for `.db` exchange files (e.g., `Job_Date_Inspector.db`).
- [ ] **GAEB Mapping:** Map door attributes and errors to the hierarchical GAEB BoQ structure.
- [ ] **Media:** Photo documentation (linked via `attachments`).
- [ ] **Validation:** Define strict DIN/EN validation rules for technical fields.

## 8. Technical Investigations
- **Error Source:** "Fehler verwalten" reads from local `working.db` populated during job checkout.
- **Search Logic:** `rawQuery` with `LEFT JOIN`. Indices on `doorNumber`, `doorAlias`, and `description`.

## Session Log: 2024-05-24 10:00
Confirmed "Door-as-Patient" philosophy. Identified table synchronization inventory. Prioritized Role Separation logic.

## Session Log: 2024-05-24 12:00
Validated `rebuild.ps1` for Android. Identified build failure resolution: `shrinkResources` depends on `minifyEnabled` in `android/app/build.gradle`.

## Session Log: 2024-05-24 (GAEB Integration Phase)
- **GAEB Export Service:** Developed `GaebExportService` supporting GAEB 90 (.d83) and GAEB XML 3.2 (.x83).
- **Validation & Compliance:** Successfully addressed XSD schema and GAEB business rule errors by implementing mandatory `BoQInfo` headers, currency tags, and `BoQCtgy` hierarchies.
- **Data Transformation:** Overhauled data handoff in `JobSelectionPage` to provide a flattened list of `Door` objects and their associated `ErrorCatalog` details, resolving type-safety crashes.
- **Position Logic:** Implemented standard GAEB numeration (3-digit `RNoPart` with increments of 10) to support downstream system integration.
- **Job Number Sanitization:** Added logic to strip non-numeric characters from job numbers for use in GAEB IDs, ensuring compliance with GAEB specifications.
- **Rich Text Styling:** Refined HTML styling within `.x83` exports to use `<span style="...">` attributes, aligning with the provided "Source of Truth" reference file for improved validator compatibility.

## Session Log: 2024-05-24 (API & Cloud Integration Phase)
- **GAEB Schema Compliance:** Resolved XSD validation errors by completing the `BoQInfo` definition, adding mandatory currency tags, unit price components (Lohn, Material, etc.), and a 3-level `BoQBkdn` hierarchy.
- **KINCHI API Implementation:** Created `KinchiApiService` to handle OIDC/Keycloak authentication and Strapi v4 file uploads. Implemented dynamic directory fetching (`getDirectories`) to resolve `400 ValidationError` when creating document records, ensuring a valid `directoryId` is used.
- **Stateless Cloud Strategy:** Decided to roll back local database tracking of KINCHI document IDs (`api_uploads` table removed). The system will now rely on the KINCHI API as the source of truth for remote documents, fetching lists directly when needed for management (e.g., deletion).
- **Cascading Deletion:** Implemented robust deletion logic in `DatabaseService` and `JobSelectionPage`. Users can now delete single, multiple, or all inspection records, which automatically cleans up associated `inspection_doors` and `inspection_door_errors` entries, while preserving master `doors` and `error_catalog` data.
- **Windows Path Normalization:** Fixed a critical "Source database not found" error during job package download/export on Windows by standardizing the `working.db` path to consistently use `getApplicationSupportDirectory()` across all `LocalDatabaseService` methods.

### Conclusion of API & Cloud Integration Phase:
The application now successfully integrates with the KINCHI Process API for GAEB file uploads, adhering to a stateless approach for cloud document management. The GAEB export functionality remains robust and compliant. Critical local database pathing issues on Windows have been resolved, and comprehensive deletion capabilities for inspection data have been added to the Manager UI.

### Current System State:
The application successfully generates validator-compliant GAEB reports and can synchronize them to the KINCHI cloud. Data isolation between the Manager's Master DB and the Inspector's Working DB is stabilized on Windows, and the management UI now supports full CRUD operations for inspection records.

---
- **Validation & Compliance:** Successfully addressed XSD schema and GAEB business rule errors by implementing mandatory `BoQInfo` headers, currency tags, and `BoQCtgy` hierarchies.
- **Data Transformation:** Overhauled data handoff in `JobSelectionPage` to provide a flattened list of `Door` objects and their associated `ErrorCatalog` details, resolving type-safety crashes.
- **Position Logic:** Implemented standard GAEB numeration (3-digit `RNoPart` with increments of 10) to support downstream system integration.

## Session Log: 2024-06-13 (Consolidation & Verification Phase)
- **Database Join Logic:** Enhanced `getErrorsForInspectionDoorIds` with an `INNER JOIN` on `error_catalog`, resolving the issue where error codes and descriptions were missing from the export data.
- **Streamlined GAEB Export:** Updated `GaebExportService` to omit technical door details (material, floor, room, manufacturer) from both XML and D83 outputs, focusing on clean, error-centric reports.
- **Robust File Handling:** Fixed variable shadowing and cross-platform pathing in the `_saveFile` routine using `path.join`.
- **End-to-End Integration Testing:** Created `gaeb_integration_test.dart` to verify the full workflow: generating test data via `TestDataGenerator`, retrieving it through `DatabaseService`, and exporting via `GaebExportService`.
- **UI & Cloud Finalization:** Integrated `KinchiApiService` into the `JobSelectionPage` to enable authenticated uploads of generated GAEB files to the cloud.
- **Data Mapping Fixes:** Resolved "MISSING_CODE" and empty description fallbacks by ensuring the correct data keys are populated during the export preparation phase.

### Current System State:
The application successfully generates validator-compliant GAEB reports and can synchronize them to the KINCHI cloud. Data isolation between the Manager's Master DB and the Inspector's Working DB is stabilized on Windows, and the management UI now supports full CRUD operations for inspection records.

---
```

### 5 Questions for Refinement

1.  **Shared Folder Access:** Since Android and Windows use the shared folder, is the inspector expected to manually copy the `.db` file using a file manager, or is there code (e.g., using `SMB` or `Network Share` packages) that handles the transfer within the Flutter app?
2.  **GAEB Positioning:** In the `.x83` export, should each "Door" be its own "Position" (PosNr), or are the "Errors" the positions and the doors just a location attribute?
3.  **Inspector Data Overlap:** If an inspector creates a *new* door in the field that doesn't exist in the Master DB, should the "Merge" logic automatically create that door in the Master repository, or should it be held for Manager review?
4.  **Deleted Records:** If an inspector deletes a door in the `working.db`, should that door be deleted from the Master DB during the merge, or should it just be "Unlinked" from that specific inspection?
5.  **Search Performance:** As the Master DB grows on the Windows machine, will the search functionality need to support server-side-style indexing, or is the volume of doors small enough for standard SQLite queries to remain fast?

<!--
[PROMPT_SUGGESTION]Refine the "Merge Logic" code to handle new doors created by inspectors.[/PROMPT_SUGGESTION]
[PROMPT_SUGGESTION]Draft the GAEB XML structure for mapping doors to positions.[/PROMPT_SUGGESTION]
