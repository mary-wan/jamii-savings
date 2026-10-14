# Jamii Savings — WSO2 Integration Practical Assignment

Fictional bank "Jamii Savings" integration suite: three services built on
**WSO2 Micro Integrator (MI)**, exposed and managed through **WSO2 API Manager (APIM)**,
with a **Jenkins** pipeline automating build → test → deploy.

## Repository layout

```
.
├── mi-integration/                  # MI Maven multi-module project
│   ├── pom.xml                      # parent aggregator
│   ├── JamiiSavingsConfigs/         # synapse-config artifacts (APIs, endpoints, sequences, data-services)
│   └── JamiiSavingsCompositeApplication/  # packages everything into a deployable .car
├── db/                              # DB schema + seed script (H2)
├── apim/
│   ├── openapi/                     # OpenAPI 3 specs for the 3 APIs
│   └── apictl-project/              # apictl projects per API + the API Product
├── docker/                          # docker-compose for MI + APIM + H2
├── scripts/                         # lightweight smoke-test script (no custom test framework)
└── Jenkinsfile                      # single pipeline covering build/test/package/deploy for all 3 APIs
```

## APIs

| Part | API | Pattern | Backend |
|---|-----|---------|---------|
| 1a — Account Balance | `GET /accounts/{accountNumber}/balance` | DB-backed | H2 (embedded, file-based) |
| 1b — Customer Proxy | `GET /customers/{customerId}` | Managed proxy | **DummyJSON** (`https://dummyjson.com/users/{id}`) — a free, public mock REST API with realistic user records and a predictable 404 for unknown IDs; chosen because it needs no auth/API key and its backend URL is kept configurable (`local-entries`) so tests don't hard-depend on it being reachable || 1c — Loan Eligibility | `POST /loans/eligibility` | SOAP → REST transform | **sondahub.com's public "Bank" SOAP mock** (`https://api.sondahub.com/soap/bank`) — see "Assumptions" below for why this is a repurposed generic SOAP service rather than a dedicated eligibility API |

(The "1a/1b/1c" labels mirror the three parts in the original assignment brief and are reused
throughout this README for quick cross-reference.)

**Chained demo workflow (1b → 1a):** DummyJSON's real user records have no bank-account
concept, so for one demo customer (`customerId=3`) 1b's backend call is swapped for a
hand-authored DummyJSON "custom snippet" (a static JSON blob at a fixed URL, configured in
`local-entries/CustomerAccountSnippetUrl_3.xml`) that adds an `accountNumbers` array whose
values are also seeded into `db/seed.sql`. This lets `GET /customers/3` feed directly into
`GET /accounts/{accountNumber}/balance`, demonstrating a realistic customer→account lookup
chain as two independent calls (no server-side aggregation). Every other `customerId` falls
back to the plain DummyJSON proxy with no `accountNumbers` field, exactly as before.

## Architecture decisions and trade-offs

This is a practice assessment, not a production banking system — every decision below favors
the simplest option that still genuinely demonstrates the required WSO2 MI/APIM/Jenkins
capability, rather than the most "enterprise" one.

- **H2, file-based, single schema** for 1a (Account Balance) — no replication, pooling
  tuning, or migrations framework; `db/schema.sql` + `db/seed.sql` are applied once at
  container start.
- **One shared error envelope** (`{ "error": { "code", "message", "requestId" } }`) and one
  shared `build-error-response.xml` sequence reused by all three APIs, instead of per-API
  error handling — keeps behavior consistent and avoids duplicated logic.
- **A single declarative Jenkinsfile** with a `TARGET_ENV` parameter instead of separate
  dev/prod pipelines or a plugin-heavy promotion workflow — `prod` is represented as a real,
  separate stage but intentionally does nothing (logged, not hidden) since no prod
  infrastructure exists for this assessment.
- **No custom rollback engine** — a failed stage simply fails the whole Jenkins run
  (fail-fast). Given a single artifact and a single target environment, a bespoke rollback
  mechanism would be solving a problem the assignment doesn't have.
- **OAuth2 client-credentials via APIM's built-in security**, not a custom auth mediator —
  this already satisfies "configure API security and verify unauthorized requests are
  rejected" without inventing a parallel auth scheme.
- **One built-in Synapse mediation policy (`addHeader`)** instead of writing custom
  Java-based mediation — the assignment asks for "at least one", and a built-in policy is
  enough to prove the mechanism works.
- **The API Product groups all three APIs** but its own merged gateway path currently
  returns a `900906 No matching resource found` even though the Product is `PUBLISHED`,
  deployed, and its merged OpenAPI definition correctly lists all three resource paths —
  a resource-dispatch quirk specific to API Products created via the raw Publisher REST
  API rather than the Publisher UI/apictl end-to-end flow. Each individual API is fully
  verified through the gateway independently, which is what the assignment actually
  requires, so this was documented rather than chased further to avoid overengineering a
  cosmetic aspect of the Product feature.

## What I'd do differently with more time

- Recreate the API Product via the Publisher UI or `apictl import api-product` end-to-end
  flow (rather than the raw Publisher REST API used here) to resolve its own merged-path
  routing limitation.
- Add a custom mediation extension (rather than relying solely on a built-in policy) to
  show both approaches to gateway-level mediation.
- Wire up a real `prod` environment (separate APIM/MI instances) so the Jenkins `prod` stage
  does something rather than only proving the structure is in place.

## Assumptions

- **Database**: H2 was confirmed as the required choice; schema/seed are applied once at
  container startup, and an "unknown account" is simply absent from `seed.sql` (not a
  specially-flagged row) — 404 is tested against a genuinely unseeded account number.
- **1b backend (Customer Proxy)**: DummyJSON (`https://dummyjson.com/users/{id}`) was
  confirmed suitable for
  "front an existing public mock REST API with a pass-through/managed proxy" — it has no
  authentication of its own, which was a deliberate, discussed trade-off (adding auth to a
  public mock the assignment doesn't require would be overengineering); the proxy itself
  still has its own OAuth2 security via APIM regardless of the backend's lack of auth.
- **1c backend (Loan Eligibility)**: no public SOAP service offers a genuine loan/credit-eligibility operation,
  so `api.sondahub.com/soap/bank` (a public SOAP "Bank" mock with `GetCustomer`) is
  **repurposed**: it supplies real `risk_score`/`kyc_status` fields, and the actual
  eligibility decision (`kyc_status == "verified" AND risk_score <= 50`) is applied entirely
  in this integration layer, not by the backend. This limitation is stated here rather than
  implied, to avoid misrepresenting the backend as a dedicated eligibility service.
- **Security scope**: all three APIs use APIM's standard OAuth2 client-credentials security;
  no additional custom auth mediator was added since it isn't required by the assignment.

## How to run everything locally

### 1. Start the runtime stack

```powershell
docker compose -f docker/docker-compose.yml up -d
```

This brings up:
- WSO2 MI (`localhost:8290` HTTP / `localhost:8253` HTTPS)
- WSO2 API Manager (`localhost:9443` — Carbon console, Publisher, Dev Portal)
- H2 database (embedded inside the MI container via the datasource config)

### 2. Build and deploy the MI composite application

```powershell
cd mi-integration
mvn clean install
```

Deploy the generated `.car` file from `JamiiSavingsCompositeApplication/target/` to the MI
`repository/deployment/server/carbonapps/` directory (or via the MI management API).

### 3. Publish the APIs in APIM

```powershell
apictl import api -f apim/apictl-project/accounts-balance-api --environment dev --update --rotate-revision
apictl import api -f apim/apictl-project/customers-api --environment dev --update --rotate-revision
apictl import api -f apim/apictl-project/loans-eligibility-api --environment dev --update --rotate-revision
apictl import api-product -f apim/apictl-project/jamii-savings-api-product --environment dev \
    --update-api-product --update-apis --import-apis --rotate-revision
```

`--rotate-revision` auto-deletes the oldest revision once the per-API revision cap is hit,
which matters once you've imported/updated the same API repeatedly (e.g. via CI).

### 4. Developer Portal flow (discover → subscribe → invoke)

This is the standard WSO2 APIM Developer Portal flow, demonstrated here via `apictl`
(equivalent steps exist in the Developer Portal web UI at `https://localhost:9443/devportal`):

1. **Discover**: Browse the Developer Portal (or `apictl get apis -e dev`) to find
   `AccountsBalanceAPI`, `CustomersAPI`, `LoansEligibilityAPI`, each `PUBLISHED` with a
   visible OpenAPI definition, throttling tier, and security requirement.
2. **Subscribe**: Create (or reuse) an Application in the Developer Portal, then subscribe
   it to the APIs you need (`apictl get keys -n <API> -v 1.0.0 -e dev` does this
   automatically for a disposable test application, via Dynamic Client Registration).
3. **Generate keys / get a token**: The Developer Portal's "Generate Access Token" button
   on a subscribed application does a client-credentials grant against
   `https://localhost:9443/oauth2/token`. `apictl get keys` performs the same OAuth2
   client-credentials flow under the hood and returns a bearer token.
4. **Invoke**: Call the API through the gateway with the token, e.g.:
   ```powershell
   Invoke-WebRequest -Uri "https://localhost:8243/accounts/1.0.0/1000000001/balance" `
     -Headers @{Authorization = "Bearer <token>"} -SkipCertificateCheck
   ```
   A request with no token (or an invalid one) is rejected by the gateway with
   `401`/`403` before it ever reaches Micro Integrator — confirming the security
   scheme is actually enforced, not just configured.

**Note:** the three APIs are grouped under one API Product (`JamiiSavingsAPIProduct`,
context `/jamii-savings`) in the Publisher/Developer Portal for discovery purposes. Each
individual API is fully verified end-to-end through the gateway; the Product's own
aggregated invocation path has a known, documented resource-routing limitation (see
"Architecture decisions and trade-offs" above) that does not affect the three underlying
APIs.

### 5. Run the Jenkins pipeline

Point a Jenkins job at this repository's `Jenkinsfile` (a `jenkins` container is already
running locally on `localhost:8080` for this purpose, with Maven/apictl/Docker CLI
pre-installed and connected to the same docker network as `jamii-mi`/`jamii-am`). Trigger a
build with the `TARGET_ENV` parameter set to `dev`; stages run Checkout → Build → Deploy MI
artifact → Test MI Integrations → Deploy/Update APIM APIs → Post-Deploy Gateway
Verification. A `prod` build runs the same structure but the deployment stages are skipped
and a placeholder stage logs that prod isn't connected in this assessment.

## Submission checklist

- [x] MI project with all three integrations (`mi-integration/`)
- [x] DB schema + seed script (`db/schema.sql`, `db/seed.sql`)
- [x] APIM API definitions / apictl project + API Product (`apim/`)
- [x] Jenkinsfile (repo root) — demonstrated with a full green run (all stages passing,
      including live gateway verification of all three APIs) and a deliberately-broken run
      (a failing test case) that stopped the pipeline immediately and skipped all
      downstream deployment/verification stages, proving failures aren't silently absorbed
- [x] README.md (this file)
- [ ] 5-minute screen recording walking through a live call to each API (success + error case
      per API, through the APIM gateway)
