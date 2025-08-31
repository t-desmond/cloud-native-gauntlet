use crate::models::{state::AppState, user::{Claims, User}};
use axum::{
    extract::{Request, State},
    http::{header, StatusCode},
    middleware::Next,
    response::Response,
};
use jsonwebtoken::{decode, DecodingKey, Validation};
use std::sync::Arc;

pub async fn auth_guard(
    State(state): State<Arc<AppState>>,
    mut req: Request,
    next: Next,
) -> Result<Response, (StatusCode, &'static str)> {
    let auth_header = req
        .headers()
        .get(header::AUTHORIZATION)
        .and_then(|header| header.to_str().ok())
        .ok_or((
            StatusCode::UNAUTHORIZED,
            "Missing or invalid Authorization header",
        ))?;

    let token = auth_header
        .strip_prefix("Bearer ")
        .ok_or((StatusCode::UNAUTHORIZED, "Invalid token format"))?;

    let claims = decode::<Claims>(
        token,
        &DecodingKey::from_secret(state.config.jwt_secret.as_ref()),
        &Validation::default(),
    )
    .map_err(|_| (StatusCode::UNAUTHORIZED, "Invalid token"))?
    .claims;

    let user: User = sqlx::query_as("SELECT * FROM users WHERE id = $1")
        .bind(uuid::Uuid::parse_str(&claims.sub).unwrap())
        .fetch_one(&state.db)
        .await
        .map_err(|_| (StatusCode::UNAUTHORIZED, "User not found"))?;

    req.extensions_mut().insert(user);
    Ok(next.run(req).await)
}

pub async fn admin_guard(req: Request, next: Next) -> Result<Response, (StatusCode, &'static str)> {
    let user = req
        .extensions()
        .get::<User>()
        .ok_or((StatusCode::UNAUTHORIZED, "User not authenticated"))?;

    if user.role != "admin" {
        return Err((StatusCode::FORBIDDEN, "Admin access required"));
    }

    Ok(next.run(req).await)
}
