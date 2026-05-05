from fastapi import APIRouter, UploadFile, File, HTTPException

from app.services.telematics_service import process_telematics_file

router = APIRouter(prefix="/api/telematics", tags=["Telematics"])


@router.post("/analyze")
async def analyze_telematics_file(file: UploadFile = File(...)):
    try:
        result = await process_telematics_file(file)
        return result

    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Telematics analysis failed: {str(e)}")