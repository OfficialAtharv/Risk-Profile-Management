import httpx
from app.config import N8N_WEBHOOK_URL


async def send_video_to_n8n(video_url: str, file_name: str, prompt: str) -> dict:
    payload = {
        "success": True,
        "video_url": video_url,
        "file_name": file_name,
        "prompt": prompt,
    }

    async with httpx.AsyncClient(timeout=300.0) as client:
        response = await client.post(N8N_WEBHOOK_URL, json=payload)

    response.raise_for_status()

    try:
        return response.json()
    except Exception:
        return {"message": response.text}