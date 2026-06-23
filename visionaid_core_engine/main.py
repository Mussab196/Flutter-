import os
# Force DeepFace/TensorFlow to use CPU to prevent CUDA 500 errors
os.environ["CUDA_VISIBLE_DEVICES"] = "-1"

from fastapi import FastAPI
from api.routes import router

app = FastAPI(
    title="Aura AI Backend Architecture",
    description="Professional production-grade structure for Face Auth and Vision AI LangGraph Agent. Features modular microservices structure.",
    version="2.0.0"
)

# Includes all routes from modular api directory 
app.include_router(router)

if __name__ == "__main__":
    import uvicorn
    # Local server test runner
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
