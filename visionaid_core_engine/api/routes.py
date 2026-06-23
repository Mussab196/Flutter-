from fastapi import APIRouter, UploadFile, File, Form, HTTPException
from fastapi.responses import JSONResponse
from models.schemas import ChatRequest
from services.face_auth import register_face_internal, verify_face_internal
from agents.vision_agent import run_vision_agent
import tempfile
import os

router = APIRouter()

@router.get("/")
def root():
    return {"message": "Aura AI Backend is Running!"}

@router.get("/health")
def health_check():
    """Health check endpoint for Flutter app to verify backend connectivity."""
    return {"status": "ok", "service": "Aura AI Backend", "version": "2.0.0"}

@router.post("/register_face")
async def register_face(uid: str = Form(...), file: UploadFile = File(...)):
    """Registers user face embedding format inside Firebase."""
    with tempfile.NamedTemporaryFile(delete=False, suffix=".jpg") as tmp:
        contents = await file.read()
        tmp.write(contents)
        tmp_path = tmp.name

    try:
        result = register_face_internal(uid, tmp_path)
        return result
    finally:
        os.remove(tmp_path)

@router.post("/verify_face")
async def verify_face(file: UploadFile = File(...)):
    """Verifies Face against database users to generate token for Mobile."""
    with tempfile.NamedTemporaryFile(delete=False, suffix=".jpg") as tmp:
        contents = await file.read()
        tmp.write(contents)
        tmp_path = tmp.name

    try:
        result = verify_face_internal(tmp_path)
        return result
    finally:
        os.remove(tmp_path)

@router.post("/vision/chat")
def chat_with_vision(request: ChatRequest):
    """LangGraph Core API Route for Vision Agent.
    Returns structured error responses so Flutter can show actionable messages."""
    try:
        reply = run_vision_agent(request.message, request.uid, request.api_key)
        return {"status": "success", "reply": reply}

    except ValueError as ve:
        # Structured errors from vision_agent.py (INVALID_API_KEY, QUOTA_EXCEEDED, etc.)
        error_str = str(ve)
        error_code = "UNKNOWN_ERROR"
        error_message = error_str

        if "INVALID_API_KEY" in error_str:
            error_code = "INVALID_API_KEY"
            error_message = "Your Gemini API key is invalid or expired. Please update it in Settings."
        elif "QUOTA_EXCEEDED" in error_str:
            error_code = "QUOTA_EXCEEDED"
            error_message = "Your API quota has been used up. Try again later or upgrade your plan."
        elif "MODEL_ERROR" in error_str:
            error_code = "MODEL_ERROR"
            error_message = "The AI model is temporarily unavailable. Please try again."
        elif "AGENT_ERROR" in error_str:
            error_code = "AGENT_ERROR"
            error_message = error_str.replace("AGENT_ERROR: ", "")

        return JSONResponse(
            status_code=400,
            content={
                "status": "error",
                "error_code": error_code,
                "message": error_message,
                "detail": error_str,
            }
        )

    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={
                "status": "error",
                "error_code": "SERVER_ERROR",
                "message": "Something went wrong on the server. Please try again.",
                "detail": str(e),
            }
        )
