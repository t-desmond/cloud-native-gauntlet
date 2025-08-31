# Rust Backend API with Swagger UI Documentation

A RESTful API built with Rust using the **Axum** framework, featuring comprehensive **Swagger UI documentation**.

## Features

* User authentication (registration, login)
* Task management (create, list, delete)
* Admin user management (list, delete users)
* PostgreSQL database integration
* JWT-based authentication
* Comprehensive API documentation with Swagger UI
* Docker and Docker Compose support for easy deployment
* PgAdmin for database management

---

## Prerequisites

* Rust (latest stable version)
* Docker and Docker Compose
* `cargo` installed for building locally

---

## Getting Started

### Environment Setup

1. Copy the example environment file:

```bash
cp .env.example .env
```

2. Edit `.env` with your configuration:

---

### Running with Docker Compose

Start the backend API, PostgreSQL database, and PgAdmin with:

```bash
docker compose up -d
```

Services will be available at:

* **Backend API:** `http://localhost:3000`
* **PostgreSQL:** `localhost:6500`
* **PgAdmin:** `http://localhost:5050`

---

### Database Setup

After starting the services, run database migrations using **SQLx CLI**:

```bash
# Install SQLx CLI if not already installed
cargo install sqlx-cli --no-default-features --features native-tls,postgres

# Run migrations
sqlx migrate run
```

---

### Accessing PgAdmin

1. Open your browser at: `http://localhost:5050`
2. Login with:

   * Email: `admin@admin.com`
   * Password: `password123`
3. Add a new server with the following details:

   * Host: `postgres` (inside Docker network)
   * Port: `5432`
   * Username: `admin`
   * Password: `password123`
   * Database: `database`

> Adjust credentials according to your `.env` file.

---

### Running Locally

```bash
cargo run
```

Application starts on: `http://localhost:3000`

---

### Running with Docker

Build and run the Docker container:

```bash
# Build the Docker image
docker build -t task-api:latest .

# Run the container
docker run -d -p 3000:3000 \
  -e DATABASE_URL=postgresql://admin:password123@localhost:6500/database \
  -e JWT_SECRET=your_ultra_secure_secret \
  -e APP_HOST=0.0.0.0 \
  -e APP_PORT=3000 \
  task-api:latest
```

---

## API Documentation

Swagger UI documentation is available at:

```
http://localhost:3000/swagger-ui
```

OpenAPI JSON specification is available at:

```
http://localhost:3000/api-docs/openapi.json
```

---

### Authentication

Most endpoints require **JWT authentication**. After login, include the token in the `Authorization` header:

```
Authorization: Bearer <your-jwt-token>
```


### API Endpoints

#### Authentication

- `POST /api/auth/register` - Register a new user
- `POST /api/auth/login` - Login and receive a JWT token

#### Tasks

- `POST /api/tasks` - Create a new task (authenticated)
- `GET /api/tasks` - List all tasks for the current user (authenticated)
- `DELETE /api/tasks/{id}` - Delete a task by ID (authenticated)

#### Admin

- `GET /api/admin/users` - List all users (admin only)
- `DELETE /api/admin/users/{id}` - Delete a user by ID (admin only)