import uuid
from pathlib import Path
from fastapi import UploadFile
from app.config import UPLOAD_DIR, BACKEND_PUBLIC_URL

VIDEO_UPLOAD_DIR = UPLOAD_DIR / "videos"
VIDEO_UPLOAD_DIR.mkdir(parents=True, exist_ok=True)


async def save_upload_file(upload_file: UploadFile) -> dict:
    original_name = upload_file.filename or "driver_video.mp4"
    extension = Path(original_name).suffix or ".mp4"

    unique_name = f"{uuid.uuid4().hex}{extension}"
    file_path = VIDEO_UPLOAD_DIR / unique_name

    content = await upload_file.read()

    with open(file_path, "wb") as f:
        f.write(content)

    public_url = f"{BACKEND_PUBLIC_URL}/uploads/videos/{unique_name}"

    return {
        "file_path": str(file_path),
        "video_url": public_url,
        "file_name": original_name,
    }