# Generates the Flutter platform folders (android/, windows/) around our code
# and applies the app name. Safe to run more than once: existing files are kept.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

flutter create . --platforms=android,windows --org com.filip --project-name test_capture

# Window title + exe display name
$main = 'windows/runner/main.cpp'
if (Test-Path $main) {
  (Get-Content $main) -replace 'L"test_capture"', 'L"TestCapture"' -replace 'Size size\(1280, 720\)', 'Size size(1440, 900)' | Set-Content $main
}
$rc = 'windows/runner/Runner.rc'
if (Test-Path $rc) {
  (Get-Content $rc) -replace '"test_capture"', '"TestCapture"' -replace 'test_capture.exe', 'TestCapture.exe' | Set-Content $rc
}

$cmake = 'windows/CMakeLists.txt'
if (Test-Path $cmake) {
  (Get-Content $cmake) -replace 'set\(BINARY_NAME "test_capture"\)', 'set(BINARY_NAME "TestCapture")' | Set-Content $cmake
}

Write-Host "Done. Now run:  flutter run -d windows   (PC hub)"
Write-Host "            or  flutter run -d <your-phone>  (Android, USB debugging on)"
