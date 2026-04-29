from pydantic import BaseModel
from typing import Optional, Any


class VisionAnalyzeResponse(BaseModel):
    success: bool
    analysis_id: str
    file_name: str
    status: str
    message: str


class VisionResultResponse(BaseModel):
    success: bool
    analysis_id: str
    status: str
    result: Optional[Any] = None