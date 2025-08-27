-- Seed an admin user for development purposes
INSERT INTO "users" (id, name, email, password, role, verified, created_at, updated_at)
VALUES (
    uuid_generate_v4(),
    'Admin User',
    'admin@example.com',
    -- adminpassword
    '$2b$12$o9tSf51hGQQs8u85psN2teYgTZw/HDBM8.XA8vKHpOEDTLvDlFXbC',
    'admin',
    true,
    NOW(),
    NOW()
)
ON CONFLICT (email) DO NOTHING;