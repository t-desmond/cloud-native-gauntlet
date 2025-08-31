use serde::Deserialize;

#[derive(Deserialize, Clone)]
pub struct Config {
    pub database_url: String,
    pub jwt_secret: String,
    pub host: String,
    pub port: u16,
}

impl Config {
    pub fn init() -> Self {
        dotenv::dotenv().ok();
        
        let database_url = std::env::var("DATABASE_URL").expect("DATABASE_URL must be set");
        let jwt_secret = std::env::var("JWT_SECRET").expect("JWT_SECRET must be set");
        let host = std::env::var("APP_HOST").expect("APP_HOST must be set");
        let port = std::env::var("APP_PORT").expect("APP_PORT must be set").parse().unwrap();
        
        Config {
            database_url,
            jwt_secret,
            host,
            port,
        }
    }
}