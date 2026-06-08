# Project Context: WartungsTool

## 1. Project Overview
**WartungsTool** is a specialized Flutter solution for door maintenance. It bridges field data collection on Android with office management and GAEB-compliant reporting on Windows.

## 2. Technical Stack
- **Framework:** Flutter (Android for Inspectors, Windows for Managers).
- **Database:** SQLite.
    - `sqflite` for Android field devices.
    - `sqflite_common_ffi` for the Windows Manager machine.
- **Data Exchange:** Shared folder file-based sync (No API/Cloud backend).

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
