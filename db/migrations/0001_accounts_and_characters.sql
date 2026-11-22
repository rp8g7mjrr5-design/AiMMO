-- Week 00: accounts and their characters.
-- Rule: migrations are add-only. Never DROP or RENAME anything that holds player data.

CREATE TABLE IF NOT EXISTS accounts (
    id             BIGSERIAL PRIMARY KEY,
    username       TEXT        NOT NULL,
    username_lc    TEXT        NOT NULL UNIQUE,
    password_hash  TEXT        NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_login_at  TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS characters (
    id               BIGSERIAL PRIMARY KEY,
    account_id       BIGINT      NOT NULL REFERENCES accounts(id),
    name             TEXT        NOT NULL,
    pos_x            DOUBLE PRECISION NOT NULL DEFAULT 0,
    pos_y            DOUBLE PRECISION NOT NULL DEFAULT 0,
    pos_z            DOUBLE PRECISION NOT NULL DEFAULT 0,
    yaw              DOUBLE PRECISION NOT NULL DEFAULT 0,
    appearance_seed  BIGINT      NOT NULL DEFAULT 0,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS characters_account_id_idx ON characters (account_id);
