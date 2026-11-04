-- Runs only when the PostgreSQL data volume is initialized for the first time.
CREATE SCHEMA IF NOT EXISTS lab;
CREATE TABLE IF NOT EXISTS lab.notes (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    title TEXT NOT NULL,
    body TEXT
);
