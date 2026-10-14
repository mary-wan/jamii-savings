-- Jamii Savings - accounts schema (H2)
-- Self-contained: run schema.sql then seed.sql to get a working local DB.

CREATE TABLE IF NOT EXISTS accounts (
    account_number VARCHAR(20) PRIMARY KEY,
    status         VARCHAR(10) NOT NULL CHECK (status IN ('ACTIVE', 'DORMANT', 'CLOSED')),
    balance_amount DECIMAL(15, 2) NOT NULL,
    currency       VARCHAR(3) NOT NULL DEFAULT 'KES'
);
