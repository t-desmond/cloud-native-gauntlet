-- Drop index on tasks table
DROP INDEX IF EXISTS "idx_tasks_user_id";

-- Drop users table
DROP TABLE IF EXISTS "users" CASCADE;

-- Drop tasks table
DROP TABLE IF EXISTS "tasks" CASCADE;