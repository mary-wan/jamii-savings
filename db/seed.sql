-- Jamii Savings - seed data for local/demo use.
-- Only real accounts are seeded. To test the 404 "unknown account" case,
-- request any account number that is NOT listed below (e.g. 1000000099).
-- Uses MERGE INTO (H2 upsert) so this script is safe to re-run every MI startup
-- (the datasource INIT script runs schema.sql + seed.sql on every connection).

MERGE INTO accounts (account_number, status, balance_amount, currency) KEY (account_number) VALUES
    ('1000000001', 'ACTIVE',  125430.50, 'KES'),
    ('1000000002', 'DORMANT',    500.00, 'KES'),
    ('1000000003', 'CLOSED',       0.00, 'KES'),
    -- Linked to CustomersProxyAPI's demo customerId 3 (see mi-integration/.../local-entries/
    -- CustomerAccountSnippetUrl_3.xml) so GET /customers/3 -> accountNumbers can be chained
    -- straight into GET /accounts/{accountNumber}/balance for an end-to-end workflow demo.
    ('1294572986', 'ACTIVE',  84200.00, 'KES'),
    ('1267093567', 'ACTIVE',  15320.75, 'KES');
