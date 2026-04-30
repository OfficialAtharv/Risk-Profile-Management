from fastapi import APIRouter, UploadFile, File, Form, HTTPException
from app.services.storage_service import save_upload_file
from app.services.n8n_service import send_video_to_n8n

router = APIRouter()


@router.post("/analyze")
async def analyze_video(
    video: UploadFile = File(...),
    prompt: str = Form(default="Analyze this dashcam driver video. Return only valid JSON."),
):
    try:
        saved = await save_upload_file(video)

        result = await send_video_to_n8n(
            video_url=saved["video_url"],
            file_name=saved["file_name"],
            prompt=prompt,
        )

        return result

    except Exception as e:
        print("VISION ANALYZE ERROR:", str(e))
        raise HTTPException(status_code=502, detail=str(e))