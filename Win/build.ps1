param([switch]$Offline, [switch]$SkipRuntimeSmoke)
$ErrorActionPreference = 'Stop'
$projectDir = $PSScriptRoot
$releaseDir = Join-Path (Split-Path $projectDir -Parent) 'Releases'
$localCargo = Join-Path $projectDir '.tools/cargo/bin/cargo.exe'
if (Test-Path -LiteralPath $localCargo) {
    $env:CARGO_HOME = Join-Path $projectDir '.tools/cargo'
    $env:RUSTUP_HOME = Join-Path $projectDir '.tools/rustup'
    $cargo = $localCargo
    $localLinker = Get-ChildItem -Path (Join-Path $projectDir '.tools/llvm-mingw-*/bin') -Directory | Select-Object -First 1
    if ($localLinker) {
        $env:PATH = "$($localLinker.FullName);$env:PATH"
        $env:RUSTFLAGS = '-C link-self-contained=yes'
    }
} else {
    $cargo = (Get-Command cargo -ErrorAction Stop).Source
}
$cargoArgs = @('--manifest-path', (Join-Path $projectDir 'Cargo.toml'), '--locked')
if ($Offline) { $cargoArgs += '--offline' }
& $cargo test @cargoArgs
if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
& $cargo build --release @cargoArgs
if ($LASTEXITCODE -ne 0) { throw 'Release build failed.' }
$binary = Join-Path $projectDir 'target/release/snowvibe.exe'
# Keep runtime-only failures (including missing Win32 entry points) out of releases.
if (-not $SkipRuntimeSmoke) {
$savedLocalAppData = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = Join-Path $projectDir 'build/smoke-profile'
    $smokeProcess = Start-Process -FilePath $binary -ArgumentList '--ui-preview','--smoke-test' -WindowStyle Hidden -PassThru
    if (-not $smokeProcess.WaitForExit(20000)) {
        Stop-Process -Id $smokeProcess.Id
        throw 'EXE startup smoke test timed out.'
    }
    if ($smokeProcess.ExitCode -ne 0) { throw "EXE startup smoke test failed: $($smokeProcess.ExitCode)" }
} finally {
    $env:LOCALAPPDATA = $savedLocalAppData
}
} else {
    Write-Output "Runtime UI test skipped by request; release requires live validation."
}
$manifest = Get-Content -LiteralPath (Join-Path $projectDir 'Cargo.toml') -Raw
$version = [regex]::Match($manifest, '(?m)^version\s*=\s*"([^"]+)"').Groups[1].Value
if (-not $version) { throw 'Package version missing.' }
$packageDir = Join-Path $releaseDir "SnowVibe-$version-Windows-x64"
New-Item -ItemType Directory -Force -Path $packageDir | Out-Null
Copy-Item -LiteralPath (Join-Path $projectDir 'target/release/snowvibe.exe') -Destination (Join-Path $packageDir 'SnowVibe.exe') -Force
Copy-Item -LiteralPath (Join-Path (Split-Path $projectDir -Parent) 'README.md') -Destination $packageDir -Force
Copy-Item -LiteralPath (Join-Path $packageDir 'SnowVibe.exe') -Destination (Join-Path $releaseDir "SnowVibe-$version-Windows-x64.exe") -Force
Compress-Archive -Path (Join-Path $packageDir '*') -DestinationPath (Join-Path $releaseDir "SnowVibe-$version-Windows-x64.zip") -Force
$checksums = @(
    Get-FileHash -LiteralPath (Join-Path $releaseDir "SnowVibe-$version-Windows-x64.exe") -Algorithm SHA256 |
        ForEach-Object { "$($_.Hash.ToLower())  SnowVibe-$version-Windows-x64.exe" }
    Get-FileHash -LiteralPath (Join-Path $releaseDir "SnowVibe-$version-Windows-x64.zip") -Algorithm SHA256 |
        ForEach-Object { "$($_.Hash.ToLower())  SnowVibe-$version-Windows-x64.zip" }
)
$checksums | Set-Content -LiteralPath (Join-Path $releaseDir "SnowVibe-$version-Windows-x64.sha256") -Encoding ascii
Write-Output "Releases: $releaseDir"
