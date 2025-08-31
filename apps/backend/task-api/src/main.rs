use sqlx::PgPool;
use std::sync::Arc;
use axum::serve;
use tokio::net::TcpListener;
use utoipa::OpenApi;
use utoipa_swagger_ui::SwaggerUi;

mod handlers;
mod models;
mod routes;

use crate::models::{state::AppState, config::Config};

#[derive(OpenApi)]
#[openapi(
    paths(
        handlers::task::create_task,
        handlers::task::list_tasks,
        handlers::task::delete_task,
        handlers::user::register_user,
        handlers::user::login_user,
        handlers::user::list_users,
        handlers::user::delete_user,
        handlers::health::health,
    ),
    components(
        schemas(
            models::task::Task,
            models::task::CreateTaskSchema,
            models::user::User,
            models::user::RegisterUserSchema,
            models::user::LoginUserSchema,
            models::user::Claims,
            models::response::TaskResponse,
            models::response::TaskListResponse,
            models::response::UserResponse,
            models::response::LoginResponse,
        )
    ),
    tags(
        (name = "tasks", description = "Task management endpoints"),
        (name = "users", description = "User management endpoints"),
        (name = "auth", description = "Authentication endpoints"),
        (name = "health", description = "Check app health"),
    ),
    security(
        ("api_jwt_token" = [])
    ),
    modifiers(&SecurityAddon)
)]
struct ApiDoc;

struct SecurityAddon;

impl utoipa::Modify for SecurityAddon {
    fn modify(&self, openapi: &mut utoipa::openapi::OpenApi) {
        let components = openapi.components.as_mut().unwrap();
        components.add_security_scheme(
            "api_jwt_token",
            utoipa::openapi::security::SecurityScheme::Http(
                utoipa::openapi::security::HttpBuilder::new()
                    .scheme(utoipa::openapi::security::HttpAuthScheme::Bearer)
                    .bearer_format("JWT")
                    .build(),
            ),
        );
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    
    let config = Config::init();

    let db = PgPool::connect(&config.database_url).await?;
    let state = Arc::new(AppState {
        db,
        config,
    });

    let app = routes::create_routes(state.clone())
        .merge(SwaggerUi::new("/swagger-ui").url("/api-docs/openapi.json", ApiDoc::openapi()));

    let addr = format!("{}:{}", state.config.host, state.config.port);
    let listener = TcpListener::bind(&addr).await?;
    println!("Server running at http://{}", addr);
    println!("Swagger UI available at http://{}/swagger-ui", addr);

    serve(listener, app).await?;

    Ok(())
}