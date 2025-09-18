-- Add up migration script here
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Tasks table
CREATE TABLE
  "tasks" (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4 (),
    name VARCHAR(100) NOT NULL,
    description TEXT,
    user_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW (),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW ()
  );

-- Create an index on user_id for better query performance
CREATE INDEX IF NOT EXISTS "idx_tasks_user_id" ON "tasks"("user_id");