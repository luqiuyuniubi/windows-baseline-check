#requires -version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$compiler = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw '未找到系统 .NET Framework C# 编译器。' }
foreach ($name in @('baseline-gui.ps1','baseline-check.ps1')) {
    $file = Join-Path $root $name
    $source = [IO.File]::ReadAllText($file)
    [IO.File]::WriteAllText($file,$source,(New-Object Text.UTF8Encoding($true)))
    $tokens = $null
    $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) { throw ($errors | Out-String) }
}
$target = Join-Path $root 'Windows基线检查.exe'
$argsList = @(
    '/nologo', '/target:winexe', '/platform:anycpu', '/optimize+', '/utf8output',
    ('/out:' + $target), '/reference:System.Windows.Forms.dll',
    ('/resource:' + (Join-Path $root 'baseline-gui.ps1') + ',baseline-gui.ps1'),
    ('/resource:' + (Join-Path $root 'baseline-check.ps1') + ',baseline-check.ps1'),
    (Join-Path $root 'packaging\Launcher.cs')
)
& $compiler @argsList
if ($LASTEXITCODE -ne 0) { throw 'EXE 编译失败。' }
Write-Output ('已生成单文件程序：' + $target)
