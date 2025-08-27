use axum::Json;
use serde_json::json;

#[utoipa::path(
    get,
    path = "/api/health",
    responses(
        (status = 200, description = "App up and running", body = serde_json::Value)
    )
)]
pub async fn health() -> Json<serde_json::Value> {
    Json(json!({
        "status": "Active"
    }))
}
