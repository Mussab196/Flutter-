import os
os.environ["CUDA_VISIBLE_DEVICES"] = "-1"

from deepface import DeepFace
from fastapi import HTTPException
import numpy as np
from core.config import db_client, firebase_initialized
from firebase_admin import auth

def register_face_internal(uid: str, tmp_path: str):
    """Logic to register a new user face"""
    if not firebase_initialized:
        raise HTTPException(status_code=500, detail="Firebase Admin SDK is not initialized on the server.")

    try:
        # Use DeepFace to extract embedding
        embedding_obj = DeepFace.represent(img_path=tmp_path, model_name="ArcFace", enforce_detection=False)
        if len(embedding_obj) == 0:
            raise ValueError("No face detected in the image.")
            
        face_vector = embedding_obj[0]['embedding']
        
        # Save embedding to Firestore
        db_client.collection("users").document(uid).update({
            "face_embedding": face_vector,
            "face_login_enabled": True
        })
        return {"status": "success", "message": "Face registered successfully!"}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error processing face: {str(e)}")


def calculate_cosine_distance(v1, v2):
    """Mathematical comparison of vectors"""
    v1 = np.array(v1)
    v2 = np.array(v2)
    return 1 - (np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2)))


def verify_face_internal(tmp_path: str):
    """Logic to verify face and generate custom Firebase token"""
    if not firebase_initialized:
        raise HTTPException(status_code=500, detail="Firebase Admin SDK is not initialized.")

    try:
        current_embedding_obj = DeepFace.represent(img_path=tmp_path, model_name="ArcFace", enforce_detection=False)
        current_vector = current_embedding_obj[0]['embedding']

        users_ref = db_client.collection("users").where("face_login_enabled", "==", True).stream()
        best_match_uid = None
        best_distance = 1.0
        threshold = 0.68  

        # Compare with DB
        for user_doc in users_ref:
            user_data = user_doc.to_dict()
            saved_vector = user_data.get("face_embedding")
            if saved_vector:
                dist = calculate_cosine_distance(saved_vector, current_vector)
                if dist < best_distance:
                    best_distance = dist
                    best_match_uid = user_doc.id

        if best_match_uid and best_distance < threshold:
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
