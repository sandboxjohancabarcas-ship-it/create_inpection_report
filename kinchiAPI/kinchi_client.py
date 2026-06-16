import requests
import os
from typing import Dict, Any, Optional, List

class KinchiAPIClient:
    """
    A production-ready client for the KINCHI PROCESS API.
    Handles OIDC authentication via Keycloak and provides access to API resources.
    """
    def __init__(self, base_url: str = "https://api.dev.kinchi.actihosting.de/api"):
        self.base_url = base_url.rstrip('/')
        self.auth_url = "https://keycloak.dev.kinchi.actihosting.de/realms/kinchi/protocol/openid-connect/token"
        self.session = requests.Session()

    def login(self, identifier: str, password: str) -> str:
        """Exchanges credentials for an OIDC Access Token."""
        payload = {
            "grant_type": "password",
            "client_id": "idm",
            "username": identifier,
            "password": password,
            "scope": "openid"
        }
        response = self.session.post(self.auth_url, data=payload)
        response.raise_for_status()
        
        token = response.json().get("access_token")
        self.session.headers.update({"Authorization": f"Bearer {token}"})
        return token

    def _request(self, method: str, endpoint: str, timeout: int = 30, params: Optional[Dict] = None, **kwargs) -> Any:
        """Internal helper for all API requests."""
        url = f"{self.base_url}/{endpoint.lstrip('/')}"
        response = self.session.request(method, url, timeout=timeout, params=params, **kwargs)
        response.raise_for_status()
        return self._extract_data(response.json())

    def _extract_data(self, response_json: Any) -> Any:
        """
        Recursively flattens Strapi v4 'data' and 'attributes' envelopes.
        This makes the API feel like a standard REST API.
        """
        if isinstance(response_json, list):
            return [self._extract_data(item) for item in response_json]
        
        if isinstance(response_json, dict) and "attributes" in response_json:
            # Merge attributes into the top level
            attrs = response_json.pop("attributes")
            response_json.update(attrs)
            # Recursively clean the new top-level keys
            for key, value in response_json.items():
                response_json[key] = self._extract_data(value)
            return response_json

        if isinstance(response_json, dict) and "data" in response_json:
            return self._extract_data(response_json["data"])
            
        return response_json

    def upload_file(self, file_path: str) -> int:
        """
        Uploads a raw file to the Strapi Media Library.
        Returns the ID of the uploaded file.
        """
        url = f"{self.base_url}/upload"
        with open(file_path, 'rb') as f:
            files = {'files': f}
            response = self.session.post(url, files=files, timeout=30)
        return self._extract_data(response.json())[0]['id']

    def create_document_record(self, file_id: int, directory_id: int) -> Any:
        """Links an uploaded file ID to a Directory in the documents collection."""
        payload = {
            "data": {
                "file": [file_id],
                "directory": directory_id
            }
        }
        return self._request("POST", "documents", json=payload)

    def update_resource(self, collection: str, resource_id: int, data: Dict[str, Any]) -> Any:
        """Generic PUT update for any collection (tasks, projects, etc)."""
        payload = {"data": data}
        return self._request("PUT", f"{collection}/{resource_id}", json=payload)

    def upload_and_create_document(self, file_path: str, directory_id: int) -> int:
        """
        High-level routine to:
        1. Upload a physical file to the Media Library.
        2. Create a Document record linking that file to a specific Directory.
        Returns the ID of the new Document record.
        """
        if not os.path.exists(file_path):
            raise FileNotFoundError(f"File not found: {file_path}")

        media_id = self.upload_file(file_path)
        doc_record = self.create_document_record(media_id, directory_id)
        return doc_record.get('id')

    def delete_document_record(self, document_id: int) -> Any:
        """Deletes a document record from the documents collection."""
        return self._request("DELETE", f"documents/{document_id}")

    def delete_file(self, file_id: int) -> Any:
        """Deletes a physical file from the Strapi Media Library."""
        return self._request("DELETE", f"upload/files/{file_id}")

    def delete_uploaded_document(self, document_id: int) -> None:
        """
        Orchestrates a full deletion:
        1. Fetches the document to identify associated file IDs.
        2. Deletes the Document Record.
        3. Deletes the associated physical files from the Media Library.
        """
        # Fetch with 'file' populated to find IDs before the record is gone
        doc = self.get_document(document_id, params={"populate": "file"})
        
        files = doc.get('file', [])
        if not isinstance(files, list):
            files = [files]
            
        file_ids = [f.get('id') for f in files if isinstance(f, dict) and f.get('id')]

        self.delete_document_record(document_id)
        for f_id in file_ids:
            self.delete_file(f_id)

    def get_document(self, document_id: int, params: Optional[Dict] = None) -> Dict:
        """Fetch a specific document record."""
        # Use a longer timeout as this involves a DB join (populate)
        return self._request("GET", f"documents/{document_id}", timeout=60, params=params)

    def get_file_metadata(self, file_id: int) -> Dict:
        """Fetch metadata for an uploaded file directly from the media library."""
        # Strapi v4 upload plugin endpoint
        return self._request("GET", f"upload/files/{file_id}")

    def download_file(self, file_url: str) -> bytes:
        """Downloads raw bytes from a relative or absolute Strapi URL."""
        if file_url.startswith('/'):
            # Strip '/api' from base_url to get the host
            host = self.base_url.rsplit('/api', 1)[0]
            file_url = f"{host}{file_url}"
        
        response = self.session.get(file_url, timeout=30)
        response.raise_for_status()
        return response.content

    def get_projects(self, params: Optional[Dict] = None) -> List[Dict]:
        """Fetch all project flows."""
        return self._request("GET", "project-flows", params=params)

    def get_tasks(self, params: Optional[Dict] = None) -> List[Dict]:
        """
        Fetch all tasks. 
        Uses a longer timeout (60s) as suggested for heavy DB queries.
        """
        return self._request("GET", "tasks", timeout=60, params=params)

    def get_directories(self, params: Optional[Dict] = None) -> List[Dict]:
        """Fetch available directories."""
        return self._request("GET", "directories", params=params)

    def get_clients(self, params: Optional[Dict] = None) -> List[Dict]:
        """Fetch all clients."""
        return self._request("GET", "clients", params=params)

    def get_companies(self, params: Optional[Dict] = None) -> List[Dict]:
        """Fetch all companies."""
        return self._request("GET", "companies", params=params)

    def get_equipments(self, params: Optional[Dict] = None) -> Dict:
        """Fetch equipment data."""
        return self._request("GET", "equipments", params=params)

if __name__ == "__main__":
    # --- CONFIGURATION ---
    USER = "s.bluemel@konzschaefer.de"
    PWD = "Konz2006"
    TARGET_DIR_ID = 542

    client = KinchiAPIClient()

    try:
        print("--- KINCHI DOCUMENT OPERATIONS ---")
        client.login(USER, PWD)
        print("✅ Logged in successfully.\n")

        # 1. OPERATION: CREATE DOCUMENT
        test_file = "api_test.txt"
        with open(test_file, "w") as f:
            f.write("Hello KINCHI API! This is a test document upload.")

        dirs = client.get_directories()
        target_dir = next((d for d in dirs if d.get('id') == TARGET_DIR_ID), None)

        if target_dir:
            print(f"🚀 Operation: Create Document")
            print(f"Uploading '{test_file}' to folder ID {TARGET_DIR_ID} ('{target_dir.get('name')}')")
            
            doc_id = client.upload_and_create_document(test_file, TARGET_DIR_ID)
            print(f"✅ Created Document Record ID: {doc_id}\n")

            # 2. OPERATION: VERIFY (Download Content)
            print(f"🔍 Operation: Verify Upload")
            doc_data = client.get_document(doc_id, params={"populate": "file"})
            
            # Handle different Strapi response formats for the file relation
            files = doc_data.get('file')
            if isinstance(files, list) and len(files) > 0:
                file_url = files[0].get('url')
            elif isinstance(files, dict):
                file_url = files.get('url')
            else:
                file_url = None

            if file_url:
                print(f"Downloading from: {file_url}")
                content = client.download_file(file_url)
                print(f"📄 File Content: {content.decode('utf-8')}\n")

            # 3. OPERATION: DELETE DOCUMENT
            delete_confirm = input(f"Do you want to delete Document ID {doc_id} and its associated files? (yes/no): ").lower()
            if delete_confirm == 'yes':
                print(f"🗑️ Operation: Delete Document")
                print(f"Removing Document ID {doc_id} and cleaning Media Library...")
                client.delete_uploaded_document(doc_id)
                print(f"✅ Document {doc_id} has been fully purged.")
            else:
                print(f"🚫 Document ID {doc_id} and its associated files were NOT deleted.")

        else:
            print(f"⚠️ Directory ID {TARGET_DIR_ID} not found. Document record skipped.")

        # Cleanup
        os.remove(test_file)

    except requests.exceptions.HTTPError as e:
        print(f"❌ API Error: {e.response.status_code} - {e.response.text}")
    except Exception as e:
        print(f"❌ Unexpected Error: {e}")