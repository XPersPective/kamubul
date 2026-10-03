param([string]$Apk = "$PSScriptRoot/../build/app/outputs/flutter-apk/app-release.apk")
$ErrorActionPreference = 'Stop'
$studioJdk = Join-Path $env:ProgramFiles 'Android/Android Studio/jbr'
if (!$env:JAVA_HOME -and (Test-Path "$studioJdk/bin/java.exe")) { $env:JAVA_HOME = $studioJdk }
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA/Android/sdk" }
$publishingRoot = if ($env:APP_PUBLISHING_ROOT) { $env:APP_PUBLISHING_ROOT } else { 'D:/AppPublishing' }
$certificate = "$publishingRoot/apps/kamubul/credentials/android/upload-certificate.der"
$buildTools = Get-ChildItem "$sdk/build-tools" -Directory |
    Where-Object Name -Match '^\d+\.\d+\.\d+$' |
    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (!$buildTools -or !(Test-Path $Apk) -or !(Test-Path $certificate)) {
    throw 'Release APK, public upload certificate and Android build tools are required.'
}
$signature = & "$($buildTools.FullName)/apksigner.bat" verify --print-certs $Apk
if ($LASTEXITCODE -ne 0) { throw 'Release signature verification failed.' }
$digest = [regex]::Match(($signature -join "`n"), 'certificate SHA-256 digest: ([a-fA-F0-9]{64})').Groups[1].Value
if ($digest -ne (Get-FileHash $certificate -Algorithm SHA256).Hash) {
    throw 'Release certificate does not match the permanent KamuBul upload key.'
}
$analyzer = "$sdk/cmdline-tools/latest/bin/apkanalyzer.bat"
$package = & $analyzer manifest application-id $Apk
if ($LASTEXITCODE -ne 0 -or "$package".Trim() -ne 'com.crazypenguin.kamubul') {
    throw 'Release package identity is incorrect.'
}
$debuggable = & $analyzer manifest debuggable $Apk
if ($LASTEXITCODE -ne 0 -or "$debuggable".Trim() -ne 'false') {
    throw 'Release APK must not be debuggable.'
}
# Android's archive check is separate from ELF alignment and a 16 KB device test.
& "$($buildTools.FullName)/zipalign.exe" -c -P 16 4 $Apk
if ($LASTEXITCODE -ne 0) { throw 'Release APK archive alignment check failed.' }
Write-Output 'APK signature, permanent upload certificate, package identity, non-debuggable flag and 16 KB ZIP alignment verified. ELF/device/store/ad/source/push acceptance remains separate.'
