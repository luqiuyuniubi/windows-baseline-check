#requires -version 5.1
[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [switch]$IncludeOptional,
    [switch]$NoOpen,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'reports'
}
$results = New-Object 'System.Collections.Generic.List[object]'
function Add-Result($Id, $Name, $Status, $Evidence, $Rule, $Advice) {
    $results.Add([pscustomobject][ordered]@{序号=$Id; 检查项=$Name; 结果=$Status; 检查证据=[string]$Evidence; 判断依据=$Rule; 处理建议=$Advice})
    Write-Host ('[{0}] {1}. {2}' -f $Status,$Id,$Name)
}
function Read-Reg($Path, $Name) {
    if (Test-Path -LiteralPath $Path) {
        $p = Get-ItemProperty -LiteralPath $Path
        if ($null -ne $p.PSObject.Properties[$Name]) { return $p.$Name }
    }
    return $null
}
function Check-Policy($Id,$Name,$Key,$Rule,$Test,$Advice) {
    if (-not $policy.ContainsKey($Key)) {
        Add-Result $Id $Name '需人工复核' $policyError $Rule $Advice
    } else {
        $v = [int]$policy[$Key]
        $status = if (& $Test $v) {'合规'} else {'不合规'}
        Add-Result $Id $Name $status "$Key = $v" $Rule $Advice
    }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$admin = (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$runDir = Join-Path $OutputDirectory ("{0}-{1}" -f $env:COMPUTERNAME,$stamp)
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$policy = @{}
$policyError = '无法取得本地安全策略；请使用管理员身份运行并检查系统版本。'
$tempDir = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tempDir | Out-Null
try {
    $cfg = Join-Path $tempDir 'security.inf'
    $log = Join-Path $tempDir 'secedit.log'
    $exportOutput = & secedit.exe /export /mergedpolicy /cfg $cfg /areas SECURITYPOLICY /log $log /quiet 2>&1
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $cfg)) {
        foreach ($line in Get-Content -LiteralPath $cfg) {
            if ($line -match '^\s*(\w+)\s*=\s*(-?\d+)\s*$') { $policy[$matches[1]] = $matches[2] }
        }
    } else { $policyError += ' secedit 导出失败。' }
} catch { $policyError += ' ' + $_.Exception.Message }
finally {
    # Only remove known files created by this run, never recursively delete a computed directory.
    foreach ($f in @('security.inf','secedit.log')) {
        $p = Join-Path $tempDir $f
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
    }
    Remove-Item -LiteralPath $tempDir -ErrorAction SilentlyContinue
}

Check-Policy 1 '口令重复使用次数限制' 'PasswordHistorySize' '强制密码历史 >= 5' {param($v) $v -ge 5} '本地安全策略 → 密码策略 → 强制密码历史，设置至少 5 个。'
Check-Policy 2 '口令生存周期要求' 'MaximumPasswordAge' '密码最长存留期为 1～90 天；0（永不过期）不合规' {param($v) $v -ge 1 -and $v -le 90} '密码最长存留期设置为 1～90 天；另需核查账户是否设置密码永不过期。'
Check-Policy 3 '口令锁定策略' 'LockoutBadCount' '账户锁定阈值为 1～10 次' {param($v) $v -ge 1 -and $v -le 10} '账户锁定阈值设置为 1～10 次。'
Check-Policy 4 '口令策略设置符合复杂度要求' 'PasswordComplexity' '密码复杂性要求已启用' {param($v) $v -eq 1} '启用“密码必须符合复杂性要求”。'
Check-Policy 5 '帐户锁定时间' 'LockoutDuration' '锁定时间 >= 5 分钟；-1 为管理员解锁，满足持续锁定要求；阈值必须启用' {param($v) $policy.ContainsKey('LockoutBadCount') -and [int]$policy['LockoutBadCount'] -gt 0 -and ($v -ge 5 -or $v -eq -1)} '启用账户锁定，并将锁定时间设为至少 5 分钟。'

try {
    $desktop = 'HKCU:\Control Panel\Desktop'
    $desktopPolicy = 'HKCU:\Software\Policies\Microsoft\Windows\Control Panel\Desktop'
    $screen = @{}
    foreach ($key in @('ScreenSaveActive','ScreenSaverIsSecure','ScreenSaveTimeOut','SCRNSAVE.EXE')) {
        $v = Read-Reg $desktopPolicy $key
        if ($null -eq $v) { $v = Read-Reg $desktop $key }
        $screen[$key] = $v
    }
    $ok = $screen.ScreenSaveActive -eq '1' -and $screen.ScreenSaverIsSecure -eq '1'
    $saver = [Environment]::ExpandEnvironmentVariables([string]$screen['SCRNSAVE.EXE'])
    $status = if (-not $ok) {'不合规'} elseif ([string]::IsNullOrWhiteSpace($saver) -or -not (Test-Path -LiteralPath $saver)) {'需人工复核'} else {'合规'}
    Add-Result 6 '设置屏幕锁定' $status ("检查用户={0}; 启用={1}; 恢复密码={2}; 等待秒数={3}; 屏保={4}" -f $identity.Name,$screen.ScreenSaveActive,$screen.ScreenSaverIsSecure,$screen.ScreenSaveTimeOut,$saver) '启用屏幕保护且恢复时使用密码；表格加固建议等待 300 秒' '为实际登录用户启用屏保和恢复密码，并建议等待时间为 5 分钟；切换用户后需重新检查。'
} catch { Add-Result 6 '设置屏幕锁定' '需人工复核' $_.Exception.Message '启用屏保且恢复时使用密码' '人工查看实际登录用户的屏幕保护设置。' }
Check-Policy 7 '复位帐户锁定计数器' 'ResetLockoutCount' '复位时间 >= 3 分钟，且账户锁定阈值已启用' {param($v) $v -ge 3 -and $policy.ContainsKey('LockoutBadCount') -and [int]$policy['LockoutBadCount'] -gt 0} '复位账户锁定计数器设置为至少 3 分钟。'

# Keep the effective advanced audit evidence; legacy policy alone can be overridden.
$auditEvidence = '未能读取有效审核策略。'
try {
    $raw = & auditpol.exe /get '/category:*' /r 2>&1
    if ($LASTEXITCODE -eq 0) {
        $auditEvidence = $raw -join [Environment]::NewLine
        $auditEvidence | Out-File -LiteralPath (Join-Path $runDir 'audit-policy.csv') -Encoding utf8
    }
} catch { $auditEvidence = $_.Exception.Message }
$advanced = Read-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'SCENoApplyLegacyAuditPolicy'
$auditChecks = @(
    @(8,'记录帐户登录日志','AuditLogonEvents',3),
    @(9,'启用审核对象访问的审核','AuditObjectAccess',3),
    @(10,'启用审核帐户管理的审核','AuditAccountManage',3),
    @(11,'启用审核过程追踪的审核','AuditProcessTracking',2),
    @(12,'启用审核系统事件的审核','AuditSystemEvents',3),
    @(13,'启用审核目录服务访问的审核','AuditDSAccess',3),
    @(14,'启用审核特权使用的审核','AuditPrivilegeUse',3),
    @(15,'启用审核策略更改的审核','AuditPolicyChange',3),
    @(17,'审核帐户登录事件','AuditAccountLogon',3)
)
$isDC = $null
try { $isDC = (Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4 } catch {}
foreach ($a in $auditChecks) {
    $rule = if ($a[3] -eq 2) {'至少启用失败审核'} else {'同时启用成功和失败审核'}
    $advice = '本地安全策略 → 本地策略 → 审核策略；若启用高级审核，请核对报告目录内 audit-policy.csv 的有效子类别策略。'
    if ($a[0] -eq 13 -and $null -ne $isDC -and -not $isDC) {
        Add-Result $a[0] $a[1] '不适用' '本机不是域控制器，未提供 AD 目录服务。' $rule $advice
    } elseif ($advanced -eq 1 -or $null -eq $advanced) {
        Add-Result $a[0] $a[1] '需人工复核' ("高级审核覆盖开关={0}；传统策略值={1}；请核对 audit-policy.csv。" -f $advanced,$policy[$a[2]]) $rule $advice
    } else {
        $mask = $a[3]
        Check-Policy $a[0] $a[1] $a[2] $rule {param($v) ($v -band $mask) -eq $mask} $advice
    }
}

try {
    $fw = @(Get-NetFirewallProfile -PolicyStore ActiveStore)
    $svc = Get-Service MpsSvc
    $ok = $fw.Count -eq 3 -and @($fw | Where-Object { $_.Enabled -ne $true }).Count -eq 0 -and $svc.Status -eq 'Running'
    $status = if ($ok) {'合规'} else {'不合规'}
    Add-Result 16 '防火墙配置' $status ((($fw | ForEach-Object {"$($_.Name)=$($_.Enabled)"}) -join '; ') + "; MpsSvc=$($svc.Status)") '域、专用、公用防火墙配置均开启，服务运行' '打开 Windows 防火墙，启用三个配置文件并检查防火墙服务。'
} catch { Add-Result 16 '防火墙配置' '需人工复核' $_.Exception.Message '防火墙开启且服务运行' '在 Windows 安全中心检查防火墙。' }

try {
    $products = @()
    try { $products = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct) } catch {}
    $defender = $null
    try { $defender = Get-MpComputerStatus } catch {}
    $names = ($products | ForEach-Object {$_.displayName}) -join ', '
    if ($null -ne $defender -and $defender.AMRunningMode -eq 'Normal' -and $defender.AntivirusEnabled -and $defender.RealTimeProtectionEnabled -and $defender.AntivirusSignatureAge -eq 0) {
        $status = '合规'
    } else { $status = '需人工复核' }
    $ev = "安全中心产品=$names"
    if ($null -ne $defender) { $ev += "; Defender模式=$($defender.AMRunningMode); 防病毒=$($defender.AntivirusEnabled); 实时防护=$($defender.RealTimeProtectionEnabled); 病毒库日期=$($defender.AntivirusSignatureLastUpdated); 病毒库年龄(天)=$($defender.AntivirusSignatureAge)" }
    Add-Result 18 '安装防病毒软件' $status $ev '已安装、已开启，且病毒库为最新；本地只能以当天更新作为初筛' '核查天擎或其他杀毒软件控制台、实时防护及更新状态；当天更新也需确认厂商最新版本。'
} catch { Add-Result 18 '安装防病毒软件' '需人工复核' $_.Exception.Message '杀毒软件开启且病毒库最新' '人工查看杀毒软件控制台。' }

try {
    $ports = @(21,23,135,137,138,139,445,3389)
    $tcp = @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object {$_.LocalPort -in $ports} | ForEach-Object {"TCP $($_.LocalAddress):$($_.LocalPort) PID=$($_.OwningProcess)"})
    $udp = @(Get-NetUDPEndpoint -ErrorAction Stop | Where-Object {$_.LocalPort -in $ports} | ForEach-Object {"UDP $($_.LocalAddress):$($_.LocalPort) PID=$($_.OwningProcess)"})
    $listeners = @($tcp) + @($udp)
    $status = if ($listeners.Count -gt 0) {'不合规'} else {'合规'}
    Add-Result 19 '高危端口关闭' $status ($listeners -join '; ') '21、23、135、137、138、139、445、3389 不存在 TCP 监听或 UDP 绑定；按表格严格判断' '结合业务关闭对应服务或配置防火墙；监听结果不等于网络可达性，3389 业务例外需人工确认。'
} catch { Add-Result 19 '高危端口关闭' '需人工复核' $_.Exception.Message '高危端口不开放' '使用 netstat -ano 和防火墙配置人工复核。' }

try {
    $uninstall = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')
    $pattern = '(?i)todesk|sunlogin|oray|向日葵|teamviewer|anydesk|rustdesk|远程控制|向日葵远程'
    $apps = @(Get-ItemProperty -Path $uninstall -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName -match $pattern} | ForEach-Object {$_.DisplayName})
    $procs = @(Get-Process | Where-Object {$_.ProcessName -match $pattern} | ForEach-Object {$_.ProcessName})
    $services = @(Get-Service | Where-Object { $_.Name -match $pattern -or $_.DisplayName -match $pattern } | ForEach-Object {$_.Name})
    $hits = @($apps + $procs + $services | Sort-Object -Unique)
    $status = if ($hits.Count -gt 0) {'不合规'} else {'需人工复核'}
    Add-Result 20 '远程软件' $status ("已安装软件、进程、服务命中：" + ($hits -join '; ')) '存在向日葵、ToDesk 等远程工具为不合规；未命中不能排除便携版或改名程序' '检查所有用户的软件、便携程序及授权清单，卸载未授权远程工具。'
} catch { Add-Result 20 '远程软件' '需人工复核' $_.Exception.Message '不存在未授权远程软件' '人工检查已安装程序和便携版工具。' }

foreach ($optional in @(@(21,'敏感文件存储','人工检查桌面和业务目录是否存储用户密码文件；脚本不搜索或读取文件内容。'),@(22,'浏览器密码保存','在实际使用的浏览器密码管理器中检查是否保存敏感系统密码；脚本不读取或解密浏览器密码。'))) {
    $status = if ($IncludeOptional) {'需人工复核'} else {'未启用'}
    Add-Result $optional[0] $optional[1] $status $optional[2] '图片中的可选检查项，由人工判断' $optional[2]
}

$sorted = @($results | Sort-Object 序号)
$csv = Join-Path $runDir 'baseline-results.csv'
$html = Join-Path $runDir 'baseline-report.html'
$sorted | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
$sorted | ConvertTo-Json -Depth 5 | Out-File -LiteralPath (Join-Path $runDir 'baseline-results.json') -Encoding utf8
function Escape-Html($value) { [System.Net.WebUtility]::HtmlEncode([string]$value) }
$summary = ($sorted | Group-Object 结果 | ForEach-Object {"$($_.Name)：$($_.Count)"}) -join ' ｜ '
$rows = foreach ($r in $sorted) {
    $class = switch ($r.结果) {'合规' {'pass'} '不合规' {'fail'} default {'review'}}
    '<tr class="{0}"><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td><td>{5}</td><td>{6}</td></tr>' -f $class,$r.序号,(Escape-Html $r.检查项),(Escape-Html $r.结果),(Escape-Html $r.检查证据),(Escape-Html $r.判断依据),(Escape-Html $r.处理建议)
}
@"
<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>Windows 重点基线检查报告</title>
<style>body{font:14px/1.65 'Microsoft YaHei',sans-serif;margin:32px;color:#233047;background:#f5f7fb}h1{color:#17386c}table{width:100%;border-collapse:collapse;background:white}th,td{border:1px solid #d9e0ea;padding:10px;text-align:left;vertical-align:top;word-break:break-word}th{background:#17386c;color:white}.pass td:nth-child(3){color:#128044}.fail td:nth-child(3){color:#c52b32}.review td:nth-child(3){color:#956400}p{white-space:pre-wrap}@media print{body{margin:0}th{color:black}}</style></head><body>
<h1>Windows 重点基线检查报告</h1>
<p>依据：20250627-重点基线检查项.xlsx（22 项）<br>计算机：$(Escape-Html $env:COMPUTERNAME) ｜ 检查账户：$(Escape-Html $identity.Name) ｜ 管理员：$admin<br>时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')</p>
<p>$(Escape-Html $summary)</p><p>只读检查，不修改系统安全设置。检查范围为本机与运行账户；域账户策略和其他用户设置需另行核对。高级审核启用或覆盖开关不明时需核对 audit-policy.csv；未确认的项目不计为合规。报告包含配置和软件信息，请妥善保管。</p>
<table><thead><tr><th>序号</th><th>检查项</th><th>结果</th><th>检查证据</th><th>判断依据</th><th>处理建议</th></tr></thead><tbody>$($rows -join "`n")</tbody></table></body></html>
"@ | Out-File -LiteralPath $html -Encoding utf8
Write-Host "`n$summary"
Write-Host "报告：$html"
if (-not $admin) { Write-Warning '当前不是管理员，部分项目可能无法读取；建议右键启动文件以管理员身份运行。' }
if (-not $NoOpen) { try { Invoke-Item -LiteralPath $html } catch { Write-Warning '报告已生成，请手动打开 HTML 文件。' } }
if ($PassThru) {
    [pscustomobject]@{ ReportPath=$html; Directory=$runDir; CsvPath=$csv; Results=$sorted }
}
