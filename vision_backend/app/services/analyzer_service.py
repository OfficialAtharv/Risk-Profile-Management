from typing import Dict, Any


_ANALYSIS_RESULTS: Dict[str, Dict[str, Any]] = {}


def create_pending_analysis(analysis_id: str, file_name: str, saved_path: str):
    _ANALYSIS_RESULTS[analysis_id] = {
        "analysis_id": analysis_id,
        "file_name": file_name,
        "saved_path": saved_path,
        "status": "pending",
        "result": None,
    }


def save_analysis_result(analysis_id: str, result: Any):
    if analysis_id not in _ANALYSIS_RESULTS:
        _ANALYSIS_RESULTS[analysis_id] = {
            "analysis_id": analysis_id,
            "file_name": None,
            "saved_path": None,
            "status": "completed",
            "result": result,
        }
    else:
        _ANALYSIS_RESULTS[analysis_id]["status"] = "completed"
        _ANALYSIS_RESULTS[analysis_id]["result"] = result


def get_analysis_result(analysis_id: str):
    return _ANALYSIS_RESULTS.get(analysis_id)


def mark_analysis_failed(analysis_id: str, error: str):
    if analysis_id in _ANALYSIS_RESULTS:
        _ANALYSIS_RESULTS[analysis_id]["status"] = "failed"
        _ANALYSIS_RESULTS[analysis_id]["result"] = {
            "error": error
        }


def analyze_video_local(video_path: str, prompt: str):
    return {
        "mode": "local_fallback",
        "video_path": video_path,
        "prompt": prompt,
        "summary": "Local fallback analyzer is working. n8n workflow is not connected yet.",
        "observations": [
            "Video uploaded successfully.",
            "Backend route is working.",
            "n8n analysis will be added after webhook setup."
        ],
        "risk_level": "pending"
    }