import pandas as pd
from pathlib import Path


REQUIRED_COLUMNS = [
    "driver_id",
    "trip_distance_km",
    "avg_speed",
    "max_speed",
    "speeding_percentage",
    "harsh_braking_events",
    "harsh_acceleration_events",
    "lane_change_events",
    "traffic_score",
    "road_risk_index",
    "weather_risk_index",
    "reaction_delay_seconds",
]


def read_telematics_file(file_path: str) -> pd.DataFrame:
    path = Path(file_path)
    ext = path.suffix.lower()

    if ext == ".csv":
        return pd.read_csv(path)

    if ext in [".xlsx", ".xls"]:
        return pd.read_excel(path)

    raise ValueError("Only CSV, XLSX, XLS files are allowed")


def normalize_columns(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()

    df.columns = (
        df.columns.astype(str)
        .str.strip()
        .str.lower()
        .str.replace(" ", "_")
        .str.replace("-", "_")
    )

    return df


def validate_columns(df: pd.DataFrame):
    missing = [col for col in REQUIRED_COLUMNS if col not in df.columns]

    if missing:
        raise ValueError(
            f"Missing required columns: {', '.join(missing)}"
        )


def to_number(series):
    return pd.to_numeric(series, errors="coerce").fillna(0)


def get_risk_level(score: int) -> str:
    if score >= 90:
        return "Elite Driver"
    elif score >= 75:
        return "Safe Driver"
    elif score >= 60:
        return "Moderate Risk"
    elif score >= 40:
        return "High Risk"
    else:
        return "Critical Risk"


def get_weather_label(value: float) -> str:
    if value <= 0.2:
        return "Clear / Dry"
    elif value <= 0.4:
        return "Light Rain"
    elif value <= 0.6:
        return "Heavy Rain"
    elif value <= 0.8:
        return "Dense Fog"
    elif value <= 0.95:
        return "Severe Storm"
    return "Extreme Unsafe"


def get_road_label(value: float) -> str:
    if value <= 0.2:
        return "Excellent Road"
    elif value <= 0.4:
        return "Minor Rough Patches"
    elif value <= 0.6:
        return "Frequent Bumps"
    elif value <= 0.8:
        return "Poor Surface"
    elif value <= 0.95:
        return "Hazardous Road"
    return "Extreme / Avoid"


def get_traffic_label(value: float) -> str:
    if value <= 0.2:
        return "Free Flow"
    elif value <= 0.4:
        return "Light Traffic"
    elif value <= 0.6:
        return "Moderate Traffic"
    elif value <= 0.8:
        return "Heavy Traffic"
    return "Very Chaotic Traffic"


def calculate_driver_score(row) -> int:
    score = 100

    score -= float(row["speeding_percentage"]) * 0.35
    score -= float(row["harsh_braking_events"]) * 3.0
    score -= float(row["harsh_acceleration_events"]) * 2.5
    score -= float(row["lane_change_events"]) * 1.5
    score -= float(row["traffic_score"]) * 8
    score -= float(row["road_risk_index"]) * 8
    score -= float(row["weather_risk_index"]) * 7
    score -= max(0, float(row["reaction_delay_seconds"]) - 1.0) * 6

    return int(max(0, min(100, round(score))))


def generate_recommendations(summary: dict) -> list[str]:
    recommendations = []

    if summary["average_speeding_percentage"] > 25:
        recommendations.append("Reduce overspeeding and follow road speed limits.")

    if summary["total_harsh_braking_events"] > 6:
        recommendations.append("Avoid sudden braking and maintain safer following distance.")

    if summary["total_harsh_acceleration_events"] > 6:
        recommendations.append("Avoid aggressive acceleration.")

    if summary["total_lane_change_events"] > 6:
        recommendations.append("Improve lane discipline and avoid unnecessary lane switching.")

    if summary["average_traffic_score"] > 0.6:
        recommendations.append("Drive more cautiously in dense traffic conditions.")

    if summary["average_road_risk_index"] > 0.6:
        recommendations.append("Reduce speed on rough or hazardous roads.")

    if summary["average_weather_risk_index"] > 0.6:
        recommendations.append("Increase caution during poor weather conditions.")

    if summary["average_reaction_delay_seconds"] > 1.5:
        recommendations.append("Improve reaction time and maintain better attention while driving.")

    if not recommendations:
        recommendations.append("Driving pattern looks safe based on uploaded telematics data.")

    return recommendations


def analyze_telematics(file_path: str) -> dict:
    df = read_telematics_file(file_path)
    df = normalize_columns(df)
    validate_columns(df)

    numeric_columns = [
        "trip_distance_km",
        "avg_speed",
        "max_speed",
        "speeding_percentage",
        "harsh_braking_events",
        "harsh_acceleration_events",
        "lane_change_events",
        "traffic_score",
        "road_risk_index",
        "weather_risk_index",
        "reaction_delay_seconds",
    ]

    for col in numeric_columns:
        df[col] = to_number(df[col])

    df["driver_score"] = df.apply(calculate_driver_score, axis=1)
    df["risk_level"] = df["driver_score"].apply(get_risk_level)

    average_score = int(round(df["driver_score"].mean()))
    overall_risk_level = get_risk_level(average_score)

    summary = {
        "total_records": int(len(df)),
        "total_trip_distance_km": round(float(df["trip_distance_km"].sum()), 2),
        "average_speed": round(float(df["avg_speed"].mean()), 2),
        "maximum_speed": round(float(df["max_speed"].max()), 2),
        "average_speeding_percentage": round(float(df["speeding_percentage"].mean()), 2),
        "total_harsh_braking_events": int(df["harsh_braking_events"].sum()),
        "total_harsh_acceleration_events": int(df["harsh_acceleration_events"].sum()),
        "total_lane_change_events": int(df["lane_change_events"].sum()),
        "average_traffic_score": round(float(df["traffic_score"].mean()), 2),
        "average_road_risk_index": round(float(df["road_risk_index"].mean()), 2),
        "average_weather_risk_index": round(float(df["weather_risk_index"].mean()), 2),
        "average_reaction_delay_seconds": round(float(df["reaction_delay_seconds"].mean()), 2),
    }

    condition_labels = {
        "traffic_condition": get_traffic_label(summary["average_traffic_score"]),
        "road_condition": get_road_label(summary["average_road_risk_index"]),
        "weather_condition": get_weather_label(summary["average_weather_risk_index"]),
    }

    driver_rows = df[
        [
            "driver_id",
            "driver_score",
            "risk_level",
            "speeding_percentage",
            "harsh_braking_events",
            "harsh_acceleration_events",
            "lane_change_events",
        ]
    ].to_dict(orient="records")

    return {
        "success": True,
        "module": "Telematics",
        "driver_score": average_score,
        "risk_score": average_score,
        "risk_level": overall_risk_level,
        "summary": summary,
        "conditions": condition_labels,
        "recommendation": generate_recommendations(summary),
        "drivers": driver_rows,
    }