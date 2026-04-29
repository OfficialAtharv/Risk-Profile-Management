from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from telematics_backend.app.routers.telematics import router as telematics_router

app = FastAPI(title="Telematics Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(telematics_router)


@app.get("/")
def root():
    return {
        "message": "Telematics backend running"
    }