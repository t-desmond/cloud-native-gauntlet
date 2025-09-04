# Logging Documentation

## Overview

The Task API implements comprehensive structured logging using the Rust `tracing` ecosystem. This provides structured, high-performance logging with support for multiple output formats and destinations.

## Features

- **Structured Logging**: All logs include contextual information in a structured format
- **Multiple Output Formats**: Pretty-printed for development, JSON for production
- **Request/Response Logging**: Automatic HTTP request and response logging with timing
- **Error Tracking**: Comprehensive error logging throughout the application
- **Configurable Log Levels**: Supports all standard log levels (trace, debug, info, warn, error)
- **Rolling File Logs**: Optional daily rolling file logs with log rotation
- **Performance Monitoring**: Request timing and database query performance tracking

## Configuration

Configure logging through environment variables:

### Basic Configuration

```bash
# Log level (default: info)
LOG_LEVEL=info

# Output format (default: pretty)
# Options: pretty, json
LOG_FORMAT=json

# Output destination (default: stdout)
# Options: stdout, /path/to/log/directory
LOG_OUTPUT=stdout
```

### Advanced Configuration

For fine-grained control, use the `RUST_LOG` environment variable:

```bash
# Enable debug for the app, but keep dependencies at info level
RUST_LOG=debug,hyper=info,sqlx=warn

# Trace everything (very verbose)
RUST_LOG=trace

# Only errors from all crates
RUST_LOG=error
```

## Log Levels

- **TRACE**: Very detailed information for debugging
- **DEBUG**: General debugging information
- **INFO**: General operational information (default)
- **WARN**: Warning messages for potentially problematic situations
- **ERROR**: Error messages for application failures

## Log Structure

### HTTP Request Logs

All HTTP requests are automatically logged with:

```json
{
  "timestamp": "2024-01-15T10:30:00.123Z",
  "level": "INFO",
  "fields": {
    "request_id": "123e4567-e89b-12d3-a456-426614174000",
    "method": "POST",
    "uri": "/api/tasks",
    "path": "/api/tasks",
    "status": 201,
    "duration_ms": 45
  },
  "target": "task_api::handlers::logging_middleware",
  "message": "HTTP request completed successfully"
}
```

### Application Logs

Business logic logs include relevant context:

```json
{
  "timestamp": "2024-01-15T10:30:00.123Z",
  "level": "INFO",
  "fields": {
    "user_id": "user123",
    "task_id": "task456",
    "task_name": "Complete project"
  },
  "target": "task_api::handlers::task",
  "message": "Task created successfully"
}
```

### Error Logs

Errors include full context and error details:

```json
{
  "timestamp": "2024-01-15T10:30:00.123Z",
  "level": "ERROR",
  "fields": {
    "user_id": "user123",
    "task_id": "task456",
    "error": "connection refused"
  },
  "target": "task_api::handlers::task",
  "message": "Failed to create task in database"
}
```

## File Logging

To enable file logging, set the `LOG_OUTPUT` environment variable to a directory path:

```bash
LOG_OUTPUT=/var/log/task-api
```

This will create daily rolling logs:
- `/var/log/task-api/task-api.log.2024-01-15`
- `/var/log/task-api/task-api.log.2024-01-16`

When using file logging, the application will:
- Write detailed logs to files
- Continue outputting INFO-level logs to stdout for monitoring

## Production Recommendations

### Docker/Kubernetes

```yaml
environment:
  - LOG_LEVEL=info
  - LOG_FORMAT=json
  - LOG_OUTPUT=stdout
  - RUST_LOG=info,task_api=debug
```

### Development

```yaml
environment:
  - LOG_LEVEL=debug
  - LOG_FORMAT=pretty
  - LOG_OUTPUT=stdout
```

### File-based Logging

```yaml
environment:
  - LOG_LEVEL=info
  - LOG_FORMAT=json
  - LOG_OUTPUT=/app/logs
volumes:
  - ./logs:/app/logs
```

## Monitoring Integration

The JSON log format is compatible with:

- **ELK Stack** (Elasticsearch, Logstash, Kibana)
- **Grafana Loki**
- **Fluentd**
- **AWS CloudWatch**
- **Google Cloud Logging**
- **Azure Monitor**

## Performance

- Asynchronous logging prevents blocking application threads
- Structured fields are efficiently serialized
- Log levels can be adjusted at runtime via environment variables
- File logging uses non-blocking writers with automatic rotation

## Security

- Sensitive headers (Authorization, Cookie, Token) are automatically filtered
- User passwords and secrets are never logged
- Request IDs allow correlation without exposing sensitive data

## Troubleshooting

### No logs appearing

1. Check `LOG_LEVEL` is set appropriately
2. Verify `RUST_LOG` doesn't override settings
3. Ensure log output destination is writable

### Too many logs

1. Increase `LOG_LEVEL` to `warn` or `error`
2. Use `RUST_LOG` to filter specific crates
3. Adjust request logging if needed

### File permission issues

1. Ensure the log directory exists and is writable
2. Check container user permissions for mounted volumes
3. Verify SELinux/AppArmor policies if applicable

## Examples

### Basic Usage

```bash
# Development
export LOG_LEVEL=debug
export LOG_FORMAT=pretty
cargo run

# Production
export LOG_LEVEL=info
export LOG_FORMAT=json
export LOG_OUTPUT=/var/log/task-api
cargo run
```

### Filtering Logs

```bash
# Only application logs, silence dependencies
export RUST_LOG=warn,task_api=info

# Database query debugging
export RUST_LOG=info,sqlx=debug

# HTTP client debugging
export RUST_LOG=info,reqwest=debug
```
