<#
    Jamii Savings Integration - lightweight API smoke test script (Phase 2).

    Usage:
        pwsh scripts/test-apis.ps1                     # against MI directly (default)
        pwsh scripts/test-apis.ps1 -BaseUrl https://localhost:8243 -ThroughGateway -Token "<bearer-token>"
#>
param(
    [string]$BaseUrl = "http://localhost:8290",
    [switch]$ThroughGateway,
    [string]$Token
)

$ErrorActionPreference = "Stop"
$pass = 0
$fail = 0

function Invoke-Case {
    param(
        [string]$Name,
        [string]$Method,
        [string]$Path,
        [string]$Body,
        [int]$ExpectedStatus
    )

    $uri = "$BaseUrl$Path"
    $headers = @{ "Content-Type" = "application/json" }
    if ($ThroughGateway -and $Token) {
        $headers["Authorization"] = "Bearer $Token"
    }

    try {
        if ($Body) {
            $response = Invoke-WebRequest -Uri $uri -Method $Method -Headers $headers -Body $Body -SkipHttpErrorCheck -SkipCertificateCheck
        } else {
            $response = Invoke-WebRequest -Uri $uri -Method $Method -Headers $headers -SkipHttpErrorCheck -SkipCertificateCheck
        }
        $actualStatus = [int]$response.StatusCode
    } catch {
        $actualStatus = -1
    }

    if ($actualStatus -eq $ExpectedStatus) {
        Write-Host "[PASS] $Name (expected $ExpectedStatus, got $actualStatus)" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "[FAIL] $Name (expected $ExpectedStatus, got $actualStatus)" -ForegroundColor Red
        $script:fail++
    }
}

Write-Host "=== 1a. Account Balance ===" -ForegroundColor Cyan
Invoke-Case -Name "valid account -> 200"       -Method GET -Path "/accounts/1000000001/balance" -ExpectedStatus 200
Invoke-Case -Name "unknown account -> 404"     -Method GET -Path "/accounts/1000000099/balance" -ExpectedStatus 404
Invoke-Case -Name "malformed account -> 400"   -Method GET -Path "/accounts/abc/balance"         -ExpectedStatus 400

Write-Host "`n=== 1b. Customer Proxy ===" -ForegroundColor Cyan
Invoke-Case -Name "valid customer -> 200"      -Method GET -Path "/customers/1"    -ExpectedStatus 200
Invoke-Case -Name "unknown customer -> 404"    -Method GET -Path "/customers/999"  -ExpectedStatus 404
Invoke-Case -Name "malformed customerId -> 400" -Method GET -Path "/customers/abc" -ExpectedStatus 400

Write-Host "`n=== Chained workflow: customer -> account number(s) -> balance ===" -ForegroundColor Cyan
try {
    $customerUri = "$BaseUrl/customers/3"
    $customerHeaders = @{ "Content-Type" = "application/json" }
    if ($ThroughGateway -and $Token) { $customerHeaders["Authorization"] = "******" }
    $customerResponse = Invoke-RestMethod -Uri $customerUri -Method GET -Headers $customerHeaders -SkipCertificateCheck
    $firstAccountNumber = $customerResponse.accountNumbers[0]
    if ($firstAccountNumber) {
        Write-Host "[INFO] customer 3 -> accountNumbers: $($customerResponse.accountNumbers -join ', ')" -ForegroundColor DarkGray
        Invoke-Case -Name "chained: customer 3's account -> 200" -Method GET -Path "/accounts/$firstAccountNumber/balance" -ExpectedStatus 200
    } else {
        Write-Host "[FAIL] chained: customer 3's accountNumbers was empty/missing" -ForegroundColor Red
        $script:fail++
    }
} catch {
    Write-Host "[FAIL] chained workflow: $_" -ForegroundColor Red
    $script:fail++
}

Write-Host "`n=== 1c. Loan Eligibility ===" -ForegroundColor Cyan
Invoke-Case -Name "eligible customer -> 200"         -Method POST -Path "/loans/eligibility" -Body '{"customerId":1,"requestedAmount":50000}'   -ExpectedStatus 200
Invoke-Case -Name "unknown customer -> 404"          -Method POST -Path "/loans/eligibility" -Body '{"customerId":999999999,"requestedAmount":50000}' -ExpectedStatus 404
Invoke-Case -Name "malformed customerId -> 400"      -Method POST -Path "/loans/eligibility" -Body '{"customerId":"abc","requestedAmount":50000}' -ExpectedStatus 400
Invoke-Case -Name "malformed requestedAmount -> 400" -Method POST -Path "/loans/eligibility" -Body '{"customerId":1,"requestedAmount":-5}'        -ExpectedStatus 400

Write-Host "`n=== Summary: $pass passed, $fail failed ===" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })
if ($fail -gt 0) { exit 1 } else { exit 0 }
