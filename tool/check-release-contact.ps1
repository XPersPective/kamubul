$ErrorActionPreference = 'Stop'
$androidDirectory = Join-Path $PSScriptRoot '../android'
Push-Location $androidDirectory
try {
    # These values only exercise a configuration task; no APK, key or mailbox is created.
    foreach ($case in @(
        @{ Value = ''; Accept = $false },
        @{ Value = 'hello@example.com'; Accept = $false },
        @{ Value = 'owner@sub.example.org'; Accept = $false },
        @{ Value = 'owner@kamubul.invalid'; Accept = $false },
        @{ Value = 'bad address'; Accept = $false },
        @{ Value = 'syntax-only@kamubul.dev'; Accept = $true }
    )) {
        $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("CONTACT_EMAIL=$($case.Value)"))
        try {
            # Windows PowerShell treats native stderr warnings as ErrorRecords.
            $ErrorActionPreference = 'Continue'
            $output = & ./gradlew.bat :app:checkReleaseContact "-Pdart-defines=$encoded" '-Dorg.gradle.jvmargs=-Xmx1536m -XX:MaxMetaspaceSize=768m' --console=plain 2>&1
            $passed = $LASTEXITCODE -eq 0
        } finally {
            $ErrorActionPreference = 'Stop'
        }
        if ($passed -ne $case.Accept) { throw "Unexpected contact validation result: $($case.Value)" }
        if (!$passed -and ($output -join "`n") -notmatch 'Production requires a real CONTACT_EMAIL') {
            throw 'Contact check did not fail for the intended reason.'
        }
        Write-Output "Contact case passed: $($case.Value)"
    }
    Write-Output 'Release contact validation: 6 cases passed. Mailbox ownership/delivery remains unverified.'
} finally {
    Pop-Location
}
