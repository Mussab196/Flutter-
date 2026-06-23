from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from pydantic import BaseModel
from deepface import DeepFace
try:
    from agent import run_jarvis
except ImportError:
    run_jarvis = None
import firebase_admin
from firebase_admin import credentials, auth, firestore
import tempfile
import os

app = FastAPI(title="Aura AI Face Authentication")

import json

# Try to initialize Firebase Admin SDK from environment variable or local file
firebase_initialized = False
try:
    cred_json = os.getenv("FIREBASE_CREDENTIALS")
    if cred_json:
        # Load from HF Space Secret (JSON string)
        cred_info = json.loads(cred_json)
        cred = credentials.Certificate(cred_info)
        print("Firebase Admin SDK: Initialized from Environment Variable!")
    else:
        # Fallback to local file
        cred = credentials.Certificate("serviceAccountKey.json")
        print("Firebase Admin SDK: Initialized from serviceAccountKey.json file!")
        
    firebase_admin.initialize_app(cred)
    db = firestore.client()
    firebase_initialized = True
except Exception as e:
    print(f"Warning: Firebase Admin SDK not initialized. Error: {e}")


@app.get("/")
def root():
    return {"message": "Aura AI Face Auth Backend is Running!"}

@app.post("/register_face")
async def register_face(uid: str = Form(...), file: UploadFile = File(...)):
    """
    Step 1: Get the photo from Flutter, extract the Face Embedding (Math Vector),
    and save it to Firebase Firestore under the user's document.
    """
    if not firebase_initialized:
        raise HTTPException(status_code=500, detail="Firebase Admin SDK is not initialized on the server.")

    # Save uploaded file temporarily
    with tempfile.NamedTemporaryFile(delete=False, suffix=".jpg") as tmp:
        contents = await file.read()
        tmp.write(contents)
        tmp_path = tmp.name

    try:
        # Use DeepFace (ArcFace model is very accurate) to get the math representation of the face
        # We set enforce_detection to True so it rejects images with no faces
        embedding_obj = DeepFace.represent(img_path=tmp_path, model_name="ArcFace", enforce_detection=True)
        
        # represent returns a list of faces. We take the first one.
        if len(embedding_obj) == 0:
            raise ValueError("No face detected in the image.")
            
        face_vector = embedding_obj[0]['embedding']

        # Save this vector to Firestore
        db.collection("users").document(uid).update({
            "face_embedding": face_vector,
            "face_login_enabled": True
        })

        return {"status": "success", "message": "Face registered successfully!"}

    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error processing face: {str(e)}")
    finally:
        # Clean up temporary file
        os.remove(tmp_path)


@app.post("/verify_face")
async def verify_face(file: UploadFile = File(...)):
    """
    Step 2: Get photo from Flutter login screen, extract vector, compare with ALL users in Firebase.
    If it matches anyone, generate a Custom Firebase Token for that user!
    """
    if not firebase_initialized:
        raise HTTPException(status_code=500, detail="Firebase Admin SDK is not initialized.")

    with tempfile.NamedTemporaryFile(delete=False, suffix=".jpg") as tmp:
        contents = await file.read()
        tmp.write(contents)
        tmp_path = tmp.name

    try:
        # 1. Get the embedding of the current uploaded image
        current_embedding_obj = DeepFace.represent(img_path=tmp_path, model_name="ArcFace", enforce_detection=True)
        current_vector = current_embedding_obj[0]['embedding']

        # 2. Get all users who have face login enabled
        users_ref = db.collection("users").where("face_login_enabled", "==", True).stream()
        
        import numpy as np
        def calculate_cosine_distance(v1, v2):
            v1 = np.array(v1)
            v2 = np.array(v2)
            return 1 - (np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2)))

        best_match_uid = None
        best_distance = 1.0
        threshold = 0.68  # Standard threshold for ArcFace

        # 3. Compare with every user
        for user_doc in users_ref:
            user_data = user_doc.to_dict()
            saved_vector = user_data.get("face_embedding")
            if saved_vector:
                dist = calculate_cosine_distance(saved_vector, current_vector)
                if dist < best_distance:
                    best_distance = dist
                    best_match_uid = user_doc.id

        if best_match_uid and best_distance < threshold:
            # FACE MATCHED! Generate a Firebase Custom Token
            custom_token = auth.create_custom_token(best_match_uid).decode('utf-8')
            return {
                "status": "success", 
                "message": "Face verified!", 
                "token": custom_token,
                "distance": best_distance
            }
        else:
            raise HTTPException(status_code=401, detail="Face does not match. Authentication failed.")

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Server error: {str(e)}")
    finally:
        os.remove(tmp_path)

# --- VISION AGENT ENDPOINT ---
class ChatRequest(BaseModel):
    message: str
    uid: str
    api_key: str

@app.post("/vision/chat")
def chat_with_vision(request: ChatRequest):
    if not run_jarvis:
        raise HTTPException(status_code=500, detail="Vision Agent is not loaded. Install LangGraph dependencies.")
    
    try:
        reply = run_jarvis(request.message, request.uid, request.api_key)
        return {"status": "success", "reply": reply}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Vision Error: {str(e)}")
