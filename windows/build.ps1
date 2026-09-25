$ErrorActionPreference = "Stop"

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDirectory

if (-not (Test-Path -LiteralPath ".venv\Scripts\pyside6-deploy.exe")) {
    throw "Build environment not found. Create windows\.venv and install requirements-build.txt first."
}

$vswhere = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
$vsInstall = if (Test-Path -LiteralPath $vswhere) {
    (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
} else { "" }
$vcvars = if ($vsInstall) { Join-Path $vsInstall "VC\Auxiliary\Build\vcvars64.bat" } else { "" }
$deploy = Join-Path $scriptDirectory ".venv\Scripts\pyside6-deploy.exe"
$python = Join-Path $scriptDirectory ".venv\Scripts\python.exe"
if (-not $vcvars -or -not (Test-Path -LiteralPath $vcvars)) {
    if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) { throw "MSVC x64 environment not found. Install Visual Studio C++ Build Tools." }
    $vcvars = ""
}
if (-not (Test-Path -LiteralPath $deploy)) { throw "pyside6-deploy is missing from the virtual environment" }
& $python (Join-Path $scriptDirectory "scripts\generate_icon.py")
if ($LASTEXITCODE -ne 0) { throw "Icon generation failed with exit code $LASTEXITCODE" }
$venvScripts = Join-Path $scriptDirectory ".venv\Scripts"
$venvRoot = Join-Path $scriptDirectory ".venv"
$stagingDirectory = Join-Path $scriptDirectory ".build-source"
$resolvedStaging = [System.IO.Path]::GetFullPath($stagingDirectory)
$resolvedRoot = [System.IO.Path]::GetFullPath($scriptDirectory).TrimEnd("\") + "\"
if (-not $resolvedStaging.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe build staging path: $resolvedStaging" }
if (Test-Path -LiteralPath $stagingDirectory) { Remove-Item -LiteralPath $stagingDirectory -Recurse -Force }
New-Item -ItemType Directory -Path $stagingDirectory | Out-Null
Copy-Item -LiteralPath (Join-Path $scriptDirectory "tokei_windows") -Destination (Join-Path $stagingDirectory "tokei_windows") -Recurse
Copy-Item -LiteralPath (Join-Path $scriptDirectory "run_app.py") -Destination $stagingDirectory
Copy-Item -LiteralPath (Join-Path $scriptDirectory "pysidedeploy.spec") -Destination $stagingDirectory
$stagedSpec = Join-Path $stagingDirectory "pysidedeploy.spec"
$specText = [System.IO.File]::ReadAllText($stagedSpec)
$specText = [System.Text.RegularExpressions.Regex]::Replace($specText, '(?m)^python_path\s*=.*$', "python_path = $python")
[System.IO.File]::WriteAllText($stagedSpec, $specText, [System.Text.UTF8Encoding]::new($false))
$compilerSetup = if ($vcvars) { "call `"$vcvars`" && " } else { "" }
$buildCommand = "$compilerSetup `"$deploy`" `"run_app.py`" --config-file `"pysidedeploy.spec`" --keep-deployment-files"
$oldVirtualEnv = $env:VIRTUAL_ENV
$oldPath = $env:PATH
$env:VIRTUAL_ENV = $venvRoot
$env:PATH = "$venvScripts;$oldPath"
Push-Location $stagingDirectory
try {
    cmd.exe /d /s /c $buildCommand
    if ($LASTEXITCODE -ne 0) { throw "pyside6-deploy failed with exit code $LASTEXITCODE" }
} finally {
    Pop-Location
    $env:VIRTUAL_ENV = $oldVirtualEnv
    $env:PATH = $oldPath
}

$candidate = Get-ChildItem -LiteralPath (Join-Path $stagingDirectory "deployment") -Filter "run_app.exe" -File -Recurse | Select-Object -First 1
if (-not $candidate) { throw "run_app.exe was not produced by pyside6-deploy" }
$destination = Join-Path $scriptDirectory "dist\Tokei-Windows.exe"
New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
if ($candidate.FullName -ne $destination) { Copy-Item -LiteralPath $candidate.FullName -Destination $destination -Force }
Get-FileHash -LiteralPath $destination -Algorithm SHA256 | Format-List
Write-Output "Built: $destination"
