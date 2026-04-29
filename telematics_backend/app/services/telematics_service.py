import shutil
from pathlib import Path
from uuid import uuid4

from fastapi import UploadFile

from telematics_analyzer.analyzer import analyze_telematics


UPLOAD_DIR = Path("uploads/telematics")
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)


async def save_telematics_file(file: UploadFile) -> str:
    ext = Path(file.filename).suffix.lower()

    if ext not in [".csv", ".xlsx", ".xls"]:
        raise ValueError("Only CSV, XLSX, XLS files are allowed")

    file_name = f"{uuid4().hex}{ext}"
    file_path = UPLOAD_DIR / file_name

    with file_path.open("wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    return str(file_path)


async def process_telematics_file(file: UploadFile) -> dict:
    file_path = await save_telematics_file(file)
    result = analyze_telematics(file_path)
    result["file_path"] = file_path
    return result