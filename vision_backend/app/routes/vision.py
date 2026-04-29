from uuid import uuid4

from fastapi import APIRouter, UploadFile, File, Form, HTTPException
from pydantic import BaseModel

from app.services.storage_service import save_upload_file
from app.services.n8n_service import trigger_n8n_workflow
from app.services.analyzer_service import (
    create_pending_analysis,
    save_analysis_result,
    get_analysis_result,
    mark_analysis_failed,
)

router = APIRouter()


class N8NResultPayload(BaseModel):
    analysis_id: str
    success: bool = True
    result: dict


@router.post("/analyze")
async def analyze_video(
    video: UploadFile = File(...),
    prompt: str = Form(
        default="""
Analyze this dashcam driving video.

Return ONLY valid JSON:
{
  "risk_score": 0,
  "risk_band": "low/medium/high/very high",
  "harsh_acceleration": "yes/no/unknown",
  "harsh_braking": "yes/no/unknown",
  "over_speeding": "yes/no/unknown",
  "road_condition": "clear/wet/rough/traffic/unknown",
  "collision_alert": "low/medium/high/unknown",
  "summary": "short summary",
  "recommendation": "short safety recommendation"
}
"""
    ),
):
    print("STEP 1: /api/vision/analyze received")

    allowed_extensions = (".mp4", ".mov", ".avi", ".mkv")
    file_name = video.filename or ""

    print("STEP 2: file name:", file_name)

    if not file_name.lower().endswith(allowed_extensions):
        raise HTTPException(
            status_code=400,
            detail="Unsupported video format. Use mp4, mov, avi, or mkv.",
        )

    analysis_id = uuid4().hex

    try:
        print("STEP 3: saving uploaded file")
        saved_path = await save_upload_file(video)
        print("STEP 4: file saved:", saved_path)

        create_pending_analysis(
            analysis_id=analysis_id,
            file_name=file_name,
            saved_path=saved_path,
        )

        print("STEP 5: calling n8n and waiting for direct response")
        n8n_response = await trigger_n8n_workflow(
            analysis_id=analysis_id,
            video_path=saved_path,
            file_name=file_name,
            prompt=prompt,
        )
        print("STEP 6: n8n response received:", n8n_response)

        final_result = n8n_response.get("result", n8n_response)

        save_analysis_result(analysis_id, final_result)

        return {
            "success": True,
            "analysis_id": analysis_id,
            "file_name": file_name,
            "status": "completed",
            "result": final_result,
            "message": "Analysis completed successfully.",
        }

    except Exception as e:
        print("VISION ANALYZE ERROR:", str(e))
        mark_analysis_failed(analysis_id, str(e))

        return {
            "success": False,
            "analysis_id": analysis_id,
            "file_name": file_name,
            "status": "failed",
            "result": {"error": str(e)},
            "message": "Analysis failed.",
        }


@router.get("/result/{analysis_id}")
async def get_result(analysis_id: str):
    item = get_analysis_result(analysis_id)

    if not item:
        raise HTTPException(status_code=404, detail="Analysis ID not found")

    return {
        "success": True,
        "analysis_id": analysis_id,
        "status": item["status"],
        "result": item["result"],
    }


@router.post("/n8n-result")
async def receive_n8n_result(payload: N8NResultPayload):
    print("STEP CALLBACK: n8n result received")
    print("analysis_id:", payload.analysis_id)
    print("success:", payload.success)
    print("result:", payload.result)

    if payload.success:
        save_analysis_result(payload.analysis_id, payload.result)
    else:
        mark_analysis_failed(payload.analysis_id, str(payload.result))

    return {
        "success": True,
        "message": "Result received successfully",
        "analysis_id": payload.analysis_id,
    }