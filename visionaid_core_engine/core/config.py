import os
import json
import firebase_admin
from firebase_admin import credentials, firestore, auth

def initialize_firebase():
    """Initializes Firebase Admin SDK."""
    try:
        cred_json = os.getenv("FIREBASE_CREDENTIALS")
        if cred_json:
            # Load from Environment Variable (JSON string)
            cred_info = json.loads(cred_json)
            cred = credentials.Certificate(cred_info)
            print("Firebase Admin SDK: Initialized from Environment Variable!")
        else:
            # Fallback to local file
            if os.path.exists("serviceAccountKey.json"):
                cred = credentials.Certificate("serviceAccountKey.json")
                print("Firebase Admin SDK: Initialized from serviceAccountKey.json file!")
            else:
                raise FileNotFoundError("System cannot find serviceAccountKey.json")
            
        if not firebase_admin._apps:
            firebase_admin.initialize_app(cred)
        db = firestore.client()
        return db, True
    except Exception as e:
        print(f"Warning: Firebase Admin SDK not initialized. Error: {e}")
        return None, False

db_client, firebase_initialized = initialize_firebase()
