-- =============================================================================
-- pgstack-prod — Initial database setup
-- =============================================================================
-- Executed once on first container creation via docker-entrypoint-initdb.d.
-- Assumes POSTGRES_USER=appuser (see .env.example).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Extensions
-- -----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "citext";

-- -----------------------------------------------------------------------------
-- Application schema
-- -----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS app AUTHORIZATION appuser;

-- -----------------------------------------------------------------------------
-- Lock down public schema
-- -----------------------------------------------------------------------------
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO appuser;

-- -----------------------------------------------------------------------------
-- Grant appuser full access to app schema
-- -----------------------------------------------------------------------------
GRANT ALL ON SCHEMA app TO appuser;

-- Default privileges for future objects created by appuser in app schema
ALTER DEFAULT PRIVILEGES FOR ROLE appuser IN SCHEMA app
    GRANT ALL ON TABLES TO appuser;
ALTER DEFAULT PRIVILEGES FOR ROLE appuser IN SCHEMA app
    GRANT ALL ON SEQUENCES TO appuser;

-- -----------------------------------------------------------------------------
-- Role defaults
-- -----------------------------------------------------------------------------
ALTER ROLE appuser SET search_path = app, public;
ALTER ROLE appuser SET timezone = 'America/Sao_Paulo';
