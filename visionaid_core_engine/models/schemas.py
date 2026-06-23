from pydantic import BaseModel
from typing import Optional

class ChatRequest(BaseModel):
    message: str
    uid: str
    api_key: str
    azure_api_key: Optional[str] = None

class VerificationResponse(BaseModel):
    status: str
    message: str
    token: Optional[str] = None
    distance: Optional[float] = None
