-- Initialize databases for Keycloak setup
-- This script runs automatically when PostgreSQL container starts for the first time

-- Create the main Keycloak database
CREATE DATABASE keycloak_db;

-- Grant privileges to the keycloak user
GRANT ALL PRIVILEGES ON DATABASE keycloak_db TO db_keycloak_username;