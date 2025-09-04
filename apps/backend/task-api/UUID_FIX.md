# UUID Type Mismatch Fix

## Problem

The application was encountering database errors when handling user operations:

```
error returned from database: column "user_id" is of type uuid but expression is of type text
error returned from database: operator does not exist: uuid = text
```

## Root Cause

The JWT token's `subject` field contains the user ID as a `String`, but the database schema expects the `user_id` column to be of type `UUID`. The handlers were attempting to bind string values to UUID database columns, causing type mismatch errors.

## Solution

### 1. Task Handlers Updated

All task handlers now properly convert the string user_id to UUID before database operations:

**Before:**
```rust
let user_id = token.subject;  // String
.bind(&user_id)              // Binding string to UUID column
```

**After:**
```rust
let user_id_str = &token.subject;
let user_id = uuid::Uuid::parse_str(user_id_str).map_err(|e| {
    error!(user_id_str = %user_id_str, error = %e, "Failed to parse user_id as UUID");
    (StatusCode::BAD_REQUEST, Json(json!({"status": "fail", "error": "Invalid user ID format"})))
})?;
.bind(user_id)               // Binding UUID to UUID column
```

### 2. Affected Handlers

- `create_task`: Converts user_id string to UUID before INSERT
- `list_tasks`: Converts user_id string to UUID before SELECT 
- `delete_task`: Converts user_id string to UUID before DELETE

### 3. Error Handling

Added proper error handling for malformed UUID strings:
- Returns `400 Bad Request` if user_id cannot be parsed as UUID
- Logs detailed error information with structured logging
- Provides user-friendly error messages

### 4. User Handlers

User handlers were already correct since they receive UUID types directly from path parameters:
- `delete_user`: Already uses `Path<uuid::Uuid>` which handles parsing automatically

## Benefits

1. **Type Safety**: Proper UUID handling prevents runtime database errors
2. **Better Error Messages**: Clear error responses for malformed user IDs  
3. **Consistent Logging**: Structured error logging for troubleshooting
4. **Validation**: Early validation of user ID format before database operations

## Testing

The fix was validated by:
- Successful compilation with `cargo build`
- Type checking with `cargo check`
- No breaking changes to existing functionality

## Database Schema Compatibility

The fix ensures compatibility with PostgreSQL UUID columns:
- Uses `uuid::Uuid` type for database binding
- Maintains proper type conversion from JWT string to database UUID
- Preserves existing database schema without modifications
