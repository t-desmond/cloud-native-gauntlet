use crate::{
    handlers::{
        health::health, middleware::{admin_guard, auth_guard}, task::{create_task, delete_task, list_tasks}, user::{delete_user, list_users, login_user, register_user}
    },
    models::state::AppState,
};
use axum::{
    middleware,
    routing::{delete, get, post},
    Router,
};
use std::sync::Arc;

pub fn create_routes(state: Arc<AppState>) -> Router {
    let public_routes = Router::new()
        .route("/api/auth/register", post(register_user))
        .route("/api/auth/login", post(login_user))
        .route("/api/health", get(health));

    let protected_routes = Router::new()
        .route("/api/tasks", post(create_task).get(list_tasks))
        .route("/api/tasks/{id}", delete(delete_task))
        .route_layer(middleware::from_fn_with_state(state.clone(), auth_guard));

    let admin_routes = Router::new()
        .route("/api/admin/users", get(list_users))
        .route("/api/admin/users/{id}", delete(delete_user))
        .route_layer(middleware::from_fn(admin_guard))
        .route_layer(middleware::from_fn_with_state(state.clone(), auth_guard));

    Router::new()
        .merge(public_routes)
        .merge(protected_routes)
        .merge(admin_routes)
        .with_state(state)
}
