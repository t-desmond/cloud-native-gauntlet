use crate::models::{
    response::{LoginResponse, UserResponse},
    state::AppState,
    user::{Claims, LoginUserSchema, RegisterUserSchema, User},
};
use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use bcrypt::{hash, verify, DEFAULT_COST};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use std::sync::Arc;

#[utoipa::path(
    post,
    path = "/api/auth/register",
    tag = "auth",
    request_body = RegisterUserSchema,
    responses(
        (status = 201, description = "User registered successfully", body = UserResponse),
        (status = 400, description = "Invalid input"),
        (status = 500, description = "Internal server error")
    )
)]
pub async fn register_user(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<RegisterUserSchema>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let hashed_password = hash(&payload.password, DEFAULT_COST).map_err(|_| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({
                "status": "fail",
                "error": "Failed to hash password"
            })),
        )
    })?;

    let user = sqlx::query_as::<_, User>(
        r#"
      INSERT INTO users (name, email, password, role, verified, created_at, updated_at)
      VALUES ($1, $2, $3, 'user', false, NOW(), NOW())
      RETURNING *
      "#,
    )
    .bind(payload.name)
    .bind(payload.email)
    .bind(hashed_password)
    .fetch_one(&state.db)
    .await
    .map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(json!({
                "status": "fail",
                "error": "Failed to register user",
                "details": e.to_string()
            })),
        )
    })?;

    Ok((StatusCode::CREATED, Json(UserResponse::from(user))))
}

#[utoipa::path(
    post,
    path = "/api/auth/login",
    tag = "auth",
    request_body = LoginUserSchema,
    responses(
        (status = 200, description = "User logged in successfully", body = LoginResponse),
        (status = 401, description = "Invalid credentials"),
        (status = 500, description = "Internal server error")
    )
)]
pub async fn login_user(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<LoginUserSchema>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let user = sqlx::query_as::<_, User>("SELECT * FROM users WHERE email = $1")
        .bind(&payload.email)
        .fetch_one(&state.db)
        .await
        .map_err(|e| {
            (
                StatusCode::UNAUTHORIZED,
                Json(json!({
                    "status": "fail",
                    "error": "Invalid email or password",
                    "details": e.to_string()
                })),
            )
        })?;

    let is_valid = verify(&payload.password, &user.password).map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({
                "status": "fail",
                "error": "Failed to verify password",
                "details": e.to_string()
            })),
        )
    })?;

    if !is_valid {
        return Err((
            StatusCode::UNAUTHORIZED,
            Json(json!({
                "status": "fail",
                "error": "Invalid email or password"
            })),
        ));
    }

    let now = chrono::Utc::now();
    let claims = Claims {
        sub: user.id.to_string(),
        iat: now.timestamp() as usize,
        exp: (now + chrono::Duration::hours(24)).timestamp() as usize,
    };

    let token = encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(state.config.jwt_secret.as_ref()),
    )
    .map_err(|_| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({
                "status": "fail",
                "error": "Failed to generate token"
            })),
        )
    })?;

    Ok(Json(LoginResponse {
        user: UserResponse::from(user),
        token,
    }))
}

#[utoipa::path(
    get,
    path = "/api/admin/users",
    tag = "users",
    responses(
        (status = 200, description = "List of users", body = [UserResponse]),
        (status = 401, description = "Unauthorized"),
        (status = 403, description = "Forbidden"),
        (status = 500, description = "Internal server error")
    ),
    security(
        ("api_jwt_token" = [])
    )
)]
pub async fn list_users(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let users = sqlx::query_as::<_, User>("SELECT * FROM users")
        .fetch_all(&state.db)
        .await
        .map_err(|_| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({
                    "status": "fail",
                    "error": "Failed to fetch users"
                })),
            )
        })?;

    let user_responses = users
        .into_iter()
        .map(UserResponse::from)
        .collect::<Vec<_>>();
    Ok(Json(user_responses))
}

#[utoipa::path(
    delete,
    path = "/api/admin/users/{id}",
    tag = "users",
    params(
        ("id" = uuid::Uuid, Path, description = "User ID")
    ),
    responses(
        (status = 200, description = "User deleted successfully"),
        (status = 401, description = "Unauthorized"),
        (status = 403, description = "Forbidden"),
        (status = 404, description = "User not found"),
        (status = 500, description = "Internal server error")
    ),
    security(
        ("api_jwt_token" = [])
    )
)]
pub async fn delete_user(
    State(state): State<Arc<AppState>>,
    Path(id): Path<uuid::Uuid>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let result = sqlx::query("DELETE FROM users WHERE id = $1")
        .bind(id)
        .execute(&state.db)
        .await
        .map_err(|_| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({
                    "status": "fail",
                    "error": "Failed to delete user"
                })),
            )
        })?;

    if result.rows_affected() == 0 {
        return Err((
            StatusCode::NOT_FOUND,
            Json(json!({
                "status": "fail",
                "error": "User not found"
            })),
        ));
    }

    Ok(
        Json(json!({"status": "OK", "message": format!("user {} deleted successfully", id)})),
    )
}
