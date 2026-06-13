# KINCHI PROCESS API Integration Context

## 1. Core Infrastructure
- **API Gateway:** `https://api.dev.kinchi.actihosting.de/api`
- **Identity Provider:** Keycloak (OIDC)
- **Auth Endpoint:** `https://keycloak.dev.kinchi.actihosting.de/realms/kinchi/protocol/openid-connect/token`
- **Auth Method:** OAuth2 `password` grant flow.
- **Client ID:** `idm`
- **Backend Architecture:** Strapi-based (v4), includes `upload` plugin.

## 2. Discovered Connectivity Rules
- **Subdomain Routing:**
    - `api.dev.kinchi...`: Correct target for programmatic API interaction.
    - `demo.dev.kinchi...`: Strictly for the Web User Interface (GUI). Returns 404 for API paths.
- **Response Structure:** Strapi v4 wraps everything in `data` and `attributes` keys. The client uses a **recursive flattener** (`_extract_data`) to merge these into standard dictionaries. *Note: Relation IDs are often inside nested objects.*
- **Latency/Timeouts:** Development servers require high timeouts due to cold starts or database load.
    - Standard: `timeout=30`
    - Heavy/DB queries (e.g., `/tasks`): `timeout=60`.

## 3. Verified Endpoints & State
- **GET /companies**: Confirmed working. (Example: `ID 321` is `Hans Gottsberg GmbH`).
- **GET /project-flows**: Working (Example: `ID 953` is `TEST document upload`).
- **GET /tasks**: Working.
- **GET /directories**: Working (returns list of folder objects).
- **POST /upload**: Verified for `.txt` files. Returns a Media ID (e.g., `1093`).
- **POST /documents**: Verified for linking a Media ID to a Directory ID (e.g., `Doc ID 502`).
- **DELETE /documents/{id}**: Confirmed working for record removal.
- **DELETE /upload/files/{id}**: Confirmed working for physical file removal from Media Library.
- **GET /upload/files/{id}**: Verified for direct metadata retrieval and binary download.

## 4. Active Developer Credentials
- **User:** `cabarcas@gottsberg.de`
- **Password:** `KINCHI_HiLdE21042017!`

## 5. Software Implementation (`kinchi_client.py`)
- **Class:** `KinchiAPIClient`
- **Key Features:**
    - `requests.Session()` based to maintain JWT headers across requests.
    - `_request()` wrapper handles unified error reporting and automatic data extraction/unwrapping.
    - `upload_file()`: Handles `multipart/form-data` binary upload to Strapi.
    - `create_document_record()`: Links an uploaded file to a directory.
    - `delete_uploaded_document()`: Orchestrated routine that fetches related file IDs, deletes the Document record, and subsequently purges the physical files from the Media Library.
    - `get_file_metadata()`: Direct access to the Media Library for URL extraction.

## 7. Entity Relationship Model (Highlights)
- **Company:** Top-level entity (e.g., Hans Gottsberg). Owns projects and coworkers.
- **Client:** Can be linked to a Company. Contains project references.
- **Project (project-flows):** Linked to a Client and a Location. Contains the directory structure for documents.
- **Task:** Linked to a Project. Can have an `assignee` (Personal) and `files` (Documents).
- **Personal:** Represents users/contacts. Linked to Companies or Clients.

## 6. Implementation Status & Next Steps
- **Current:** Authentication, basic CRUD for core entities, and orchestrated document/file lifecycle management (upload, link, and full purge) are functional.
- **Next Steps:** 
    - Implement `PUT` updates (e.g., changing task status).
    - Implement advanced filtering (e.g., `filters[status][$eq]=execution`).
    - Expand resource coverage (Invoices, Costs, Personal) as per `openapi.json`.

---
*Last Updated: 2024-05-23*
*Reference: openapi.json*
