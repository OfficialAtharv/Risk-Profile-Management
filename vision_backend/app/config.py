from pathlib import Path
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    APP_NAME: str = "Vision AI Backend"
    APP_ENV: str = "development"

    HOST: str = "0.0.0.0"
    PORT: int = 8000

    UPLOAD_DIR: str = "uploads"
    MAX_VIDEO_SIZE_MB: int = 100

    N8N_WEBHOOK_URL: str
    BACKEND_PUBLIC_URL: str = "http://127.0.0.1:8000"

    GOOGLE_DRIVE_FOLDER_ID: str = ""

    RESULT_TTL_MINUTES: int = 60

    class Config:
        env_file = ".env"
        extra = "ignore"


settings = Settings()

BASE_DIR = Path(__file__).resolve().parent.parent
PROJECT_DIR = BASE_DIR.parent
UPLOAD_DIR = PROJECT_DIR / settings.UPLOAD_DIR
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)