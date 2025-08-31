use chrono::prelude::*;
use serde::{Deserialize, Serialize};
use utoipa::{ToSchema, schema};

#[derive(Deserialize, sqlx::FromRow, Serialize, Clone, ToSchema)]
pub struct User {
    pub id: uuid::Uuid,
    pub name: String,
    pub email: String,
    #[serde(skip)]
    pub password: String,
    pub role: String,
    pub verified: bool,
    #[serde(rename = "createdAt")]
    #[schema(value_type = Option<String>, format = DateTime)]
    pub created_at: Option<DateTime<Utc>>,
    #[serde(rename = "updatedAt")]
    #[schema(value_type = Option<String>, format = DateTime)]
    pub updated_at: Option<DateTime<Utc>>,
}

#[derive(Serialize, Deserialize, ToSchema)]
pub struct Claims {
    pub sub: String,
    pub iat: usize,
    pub exp: usize,
}

#[derive(Deserialize, ToSchema)]
pub struct RegisterUserSchema {
    pub name: String,
    pub email: String,
    pub password: String,
}

#[derive(Deserialize, ToSchema)]
pub struct LoginUserSchema {
    pub email: String,
    pub password: String,
}