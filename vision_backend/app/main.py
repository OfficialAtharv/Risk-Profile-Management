from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.routes.vision import router as vision_router
from app.config import UPLOAD_DIR

app = FastAPI(title="Vision AI Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.mount("/uploads", StaticFiles(directory=str(UPLOAD_DIR)), name="uploads")

app.include_router(vision_router, prefix="/api/vision", tags=["Vision"])


@app.get("/")
async def root():
    return {"success": True, "message": "Vision AI Backend is running"}