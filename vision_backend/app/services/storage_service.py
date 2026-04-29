from pathlib import Path
from uuid import uuid4
from fastapi import UploadFile

from app.config import UPLOAD_DIR


async def save_upload_file(file: UploadFile) -> str:
    original_name = file.filename or "video.mp4"
    suffix = Path(original_name).suffix.lower()

    safe_name = f"{uuid4().hex}{suffix}"
    file_path = UPLOAD_DIR / safe_name

    content = await file.read()

    with open(file_path, "wb") as buffer:
        buffer.write(content)

    return str(file_path)