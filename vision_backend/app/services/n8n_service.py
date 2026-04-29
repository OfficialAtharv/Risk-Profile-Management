import httpx
from pathlib import Path

from app.config import settings


async def trigger_n8n_workflow(
    analysis_id: str,
    video_path: str,
    file_name: str,
    prompt: str,
):
    saved_file_name = Path(video_path).name

    payload = {
        "analysis_id": analysis_id,
        "video_path": video_path,
        "video_url": f"{settings.BACKEND_PUBLIC_URL}/uploads/{saved_file_name}",
        "file_name": file_name,
        "prompt": prompt,
        "callback_url": f"{settings.BACKEND_PUBLIC_URL}/api/vision/n8n-result",
        "checks": {
            "over_speeding": True,
            "harsh_braking": True,
            "harsh_acceleration": True,
            "lane_departure": True,
            "collision_alert": True,
            "road_condition": True,
        },
    }

    print("========== N8N DEBUG ==========")
    print("N8N URL:", settings.N8N_WEBHOOK_URL)
    print("Payload:", payload)
    print("===============================")

    async with httpx.AsyncClient(timeout=60) as client:
        response = await client.post(
            settings.N8N_WEBHOOK_URL,
            json=payload,
        )

        print("N8N Status:", response.status_code)
        print("N8N Response:", response.text)

        response.raise_for_status()

        try:
            return response.json()
        except Exception:
            return {"message": response.text}