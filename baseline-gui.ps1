#requires -version 5.1
[CmdletBinding()]
param([switch]$SelfTest, [string]$PreviewPath, [string]$DefaultOutputDirectory)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:enginePath = Join-Path $script:root 'baseline-check.ps1'
$script:worker = $null
$script:pending = $null
$script:lastReport = $null
$script:allResults = @()
$script:infoIndex = 0
$script:runError = $null
$script:lastOutputDirectory = $null
$script:closing = $false
$navy = [Drawing.ColorTranslator]::FromHtml('#162C4B')
$blue = [Drawing.ColorTranslator]::FromHtml('#2463EB')
$muted = [Drawing.ColorTranslator]::FromHtml('#66758A')
$bg = [Drawing.ColorTranslator]::FromHtml('#F3F6FB')
$font = New-Object Drawing.Font('Microsoft YaHei UI',9)
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

function New-Label($text,$size=9,$bold=$false) {
    $label = New-Object Windows.Forms.Label
    $label.Text = $text
    $label.AutoSize = $true
    $style = if ($bold) {[Drawing.FontStyle]::Bold} else {[Drawing.FontStyle]::Regular}
    $label.Font = New-Object Drawing.Font('Microsoft YaHei UI',$size,$style)
    $label.ForeColor = $navy
    $label.Margin = New-Object Windows.Forms.Padding(0,3,12,3)
    return $label
}
function New-Button($text,$width=110) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $text
    $b.Size = New-Object Drawing.Size($width,34)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderColor = [Drawing.ColorTranslator]::FromHtml('#D4DDEB')
    $b.BackColor = [Drawing.Color]::White
    $b.ForeColor = $navy
    $b.Cursor = [Windows.Forms.Cursors]::Hand
    $b.Margin = New-Object Windows.Forms.Padding(0,0,8,0)
    return $b
}
function Add-Log([string]$text) {
    $logBox.AppendText(('[' + (Get-Date -Format 'HH:mm:ss') + '] ' + $text + [Environment]::NewLine))
    $logBox.SelectionStart = $logBox.TextLength
    $logBox.ScrollToCaret()
}

$form = New-Object Windows.Forms.Form
$form.Text = 'Windows 重点基线检查'
$form.Size = New-Object Drawing.Size(1240,880)
$form.MinimumSize = New-Object Drawing.Size(1020,760)
$form.StartPosition = 'CenterScreen'
$form.Font = $font
$form.BackColor = $bg
$form.AutoScaleMode = 'Dpi'

$layout = New-Object Windows.Forms.TableLayoutPanel
$layout.Dock = 'Fill'
$layout.Font = $font
$layout.ColumnCount = 1
$layout.RowCount = 8
$layout.Padding = New-Object Windows.Forms.Padding(24,18,24,16)
foreach ($height in @(78,98,48,48)) {
    $layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',$height))) | Out-Null
}
$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',100))) | Out-Null
foreach ($height in @(120,90,30)) {
    $layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',$height))) | Out-Null
}
$form.Controls.Add($layout)

$header = New-Object Windows.Forms.FlowLayoutPanel
$header.Dock = 'Fill'
$header.FlowDirection = 'TopDown'
$header.WrapContents = $false
$header.Controls.Add((New-Label 'Windows 重点基线检查' 22 $true))
$header.Controls.Add((New-Label '依据 20250627 检查清单 · 22 项检查 · 本地生成报告' 10))
$layout.Controls.Add($header,0,0)

$settings = New-Object Windows.Forms.TableLayoutPanel
$settings.Dock = 'Fill'
$settings.ColumnCount = 3
$settings.RowCount = 2
$settings.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',90))) | Out-Null
$settings.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100))) | Out-Null
$settings.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',100))) | Out-Null
$settings.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',44))) | Out-Null
$settings.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',44))) | Out-Null
$settings.Controls.Add((New-Label '报告目录' 10),0,0)
$pathBox = New-Object Windows.Forms.TextBox
$pathBox.Dock = 'Fill'
$pathBox.Text = if ([string]::IsNullOrWhiteSpace($DefaultOutputDirectory)) { Join-Path $script:root 'reports' } else { $DefaultOutputDirectory }
$pathBox.Margin = New-Object Windows.Forms.Padding(0,3,12,3)
$settings.Controls.Add($pathBox,1,0)
$browse = New-Button '选择目录' 96
$settings.Controls.Add($browse,2,0)
$optional = New-Object Windows.Forms.CheckBox
$optional.Text = '加入可选人工检查：敏感文件存储、浏览器密码保存（第 21、22 项）'
$optional.AutoSize = $true
$optional.Margin = New-Object Windows.Forms.Padding(0,4,0,0)
$settings.Controls.Add($optional,1,1)
$settings.SetColumnSpan($optional,2)
$layout.Controls.Add($settings,0,1)

$actions = New-Object Windows.Forms.FlowLayoutPanel
$actions.Dock = 'Fill'
$start = New-Button '开始检查' 128
$start.BackColor = $blue
$start.ForeColor = [Drawing.Color]::White
$start.FlatAppearance.BorderSize = 0
$report = New-Button '打开完整报告' 128
$report.Enabled = $false
$folder = New-Button '打开报告目录' 128
$folder.Enabled = $false
$filterLabel = New-Label '查看' 9
$filterLabel.Margin = New-Object Windows.Forms.Padding(18,8,8,0)
$filter = New-Object Windows.Forms.ComboBox
$filter.DropDownStyle = 'DropDownList'
$filter.Width = 140
$filter.Margin = New-Object Windows.Forms.Padding(0,5,0,0)
$filter.Items.AddRange(@('全部结果','不合规','需人工复核','合规','不适用','未启用'))
$filter.SelectedIndex = 0
$actions.Controls.AddRange(@($start,$report,$folder,$filterLabel,$filter))
$layout.Controls.Add($actions,0,2)

$summary = New-Label '尚未检查 · 点击“开始检查”获取本机结果' 11 $true
$summary.Dock = 'Fill'
$summary.Padding = New-Object Windows.Forms.Padding(0,8,0,0)
$layout.Controls.Add($summary,0,3)

$grid = New-Object Windows.Forms.DataGridView
$grid.Dock = 'Fill'
$grid.ReadOnly = $true
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.AllowUserToResizeRows = $false
$grid.MultiSelect = $false
$grid.SelectionMode = 'FullRowSelect'
$grid.RowHeadersVisible = $false
$grid.AutoGenerateColumns = $false
$grid.BackgroundColor = [Drawing.Color]::White
$grid.BorderStyle = 'None'
$grid.CellBorderStyle = 'SingleHorizontal'
$grid.GridColor = [Drawing.ColorTranslator]::FromHtml('#E8EDF5')
$grid.EnableHeadersVisualStyles = $false
$grid.ColumnHeadersDefaultCellStyle.BackColor = $navy
$grid.ColumnHeadersDefaultCellStyle.ForeColor = [Drawing.Color]::White
$grid.ColumnHeadersDefaultCellStyle.Font = $font
$grid.ColumnHeadersHeight = 36
$grid.ColumnHeadersHeightSizeMode = 'DisableResizing'
$grid.RowTemplate.Height = 33
$grid.DefaultCellStyle.SelectionBackColor = [Drawing.ColorTranslator]::FromHtml('#E5EEFF')
$grid.DefaultCellStyle.SelectionForeColor = $navy
$grid.DefaultCellStyle.ForeColor = $navy
$grid.AlternatingRowsDefaultCellStyle.BackColor = [Drawing.ColorTranslator]::FromHtml('#F8FAFD')
foreach ($spec in @(@('序号',55),@('检查项',250),@('结果',120),@('判断依据',600))) {
    $column = New-Object Windows.Forms.DataGridViewTextBoxColumn
    $column.Name = $spec[0]
    $column.HeaderText = $spec[0]
    $column.Width = $spec[1]
    $column.SortMode = 'NotSortable'
    if ($spec[0] -eq '判断依据') { $column.AutoSizeMode = 'Fill'; $column.MinimumWidth = 150 }
    $grid.Columns.Add($column) | Out-Null
}
$layout.Controls.Add($grid,0,4)

$details = New-Object Windows.Forms.TextBox
$details.Dock = 'Fill'
$details.Multiline = $true
$details.ReadOnly = $true
$details.ScrollBars = 'Vertical'
$details.BackColor = [Drawing.Color]::White
$details.BorderStyle = 'FixedSingle'
$details.Margin = New-Object Windows.Forms.Padding(0,10,0,0)
$details.Text = '选中检查项，在此查看检查证据与处理建议。'
$layout.Controls.Add($details,0,5)
$logBox = New-Object Windows.Forms.TextBox
$logBox.Dock = 'Fill'
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = 'Vertical'
$logBox.BackColor = $bg
$logBox.ForeColor = $muted
$logBox.BorderStyle = 'None'
$logBox.Margin = New-Object Windows.Forms.Padding(0,8,0,0)
$layout.Controls.Add($logBox,0,6)

$footer = New-Object Windows.Forms.TableLayoutPanel
$footer.Dock = 'Fill'
$footer.ColumnCount = 2
$footer.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100))) | Out-Null
$footer.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',170))) | Out-Null
$statusLabel = New-Label '' 9
$statusLabel.Dock = 'Fill'
$statusLabel.ForeColor = $muted
$statusLabel.AutoEllipsis = $true
$footer.Controls.Add($statusLabel,0,0)
$progress = New-Object Windows.Forms.ProgressBar
$progress.Dock = 'Fill'
$progress.Margin = New-Object Windows.Forms.Padding(0,6,0,6)
$footer.Controls.Add($progress,1,0)
$layout.Controls.Add($footer,0,7)
$statusLabel.Text = if ($isAdmin) {'管理员模式 · 只读检查，不修改系统设置'} else {'普通模式 · 建议右键启动文件“以管理员身份运行”，以读取完整配置'}

function Show-Results {
    $grid.Rows.Clear()
    foreach ($r in $script:allResults) {
        if ($filter.SelectedIndex -gt 0 -and $r.结果 -ne [string]$filter.SelectedItem) { continue }
        $index = $grid.Rows.Add([object[]]@([string]$r.序号,[string]$r.检查项,[string]$r.结果,[string]$r.判断依据))
        $grid.Rows[$index].Tag = $r
        $color = switch ($r.结果) {
            '合规' {'#15804B'}
            '不合规' {'#C73540'}
            '需人工复核' {'#9A6800'}
            default {'#66758A'}
        }
        $grid.Rows[$index].Cells[2].Style.ForeColor = [Drawing.ColorTranslator]::FromHtml($color)
    }
    if ($grid.Rows.Count -gt 0) {
        $grid.CurrentCell = $grid.Rows[0].Cells[0]
        Show-Details
    } else { $details.Text = '当前筛选条件下没有结果。' }
}
function Show-Details {
    if ($null -ne $grid.CurrentRow -and $null -ne $grid.CurrentRow.Tag) {
        $r = $grid.CurrentRow.Tag
        $details.Text = "第 $($r.序号) 项 · $($r.检查项) [$($r.结果)]`r`n检查证据：$($r.检查证据)`r`n判断依据：$($r.判断依据)`r`n处理建议：$($r.处理建议)"
    }
}
function Set-Running($running) {
    $start.Enabled = -not $running
    $pathBox.Enabled = -not $running
    $browse.Enabled = -not $running
    $optional.Enabled = -not $running
    $report.Enabled = -not $running -and $null -ne $script:lastReport
    $folder.Enabled = -not $running -and $null -ne $script:lastReport
    $progress.Style = if ($running) {'Marquee'} else {'Blocks'}
    $progress.Value = if ($running) {0} else {100}
}
function Start-Scan {
    if ($null -ne $script:worker) { return }
    try {
        if (-not (Test-Path -LiteralPath $script:enginePath -PathType Leaf)) { throw '缺少 baseline-check.ps1，请将检查脚本与界面放在同一文件夹。' }
        if ([string]::IsNullOrWhiteSpace($pathBox.Text)) { throw '请先选择报告目录。' }
        $target = [IO.Path]::GetFullPath($pathBox.Text.Trim())
        $pathBox.Text = $target
        $script:allResults = @()
        $script:lastReport = $null
        $script:runError = $null
        $script:infoIndex = 0
        $grid.Rows.Clear()
        $details.Text = '正在检查，完成后可选中条目查看证据和建议。'
        $logBox.Clear()
        Add-Log '开始检查，请稍候。'
        $summary.Text = '正在检查本机安全配置…'
        Set-Running $true
        $script:worker = [PowerShell]::Create()
        $null = $script:worker.AddCommand($script:enginePath).AddParameter('OutputDirectory',$target).AddParameter('NoOpen').AddParameter('PassThru')
        if ($optional.Checked) { $null = $script:worker.AddParameter('IncludeOptional') }
        $script:pending = $script:worker.BeginInvoke()
        $timer.Start()
    } catch {
        $script:runError = $_.Exception.Message
        Add-Log ('无法开始：' + $script:runError)
        $summary.Text = '检查未启动，请查看下方提示。'
        if ($null -ne $script:worker) { $script:worker.Dispose(); $script:worker = $null }
        Set-Running $false
        $progress.Value = 0
    }
}
function Update-Scan {
    if ($null -eq $script:worker) { return }
    try {
        $information = $script:worker.Streams.Information
        while ($script:infoIndex -lt $information.Count) {
            Add-Log ([string]$information[$script:infoIndex].MessageData)
            $script:infoIndex++
        }
        if (-not $script:pending.IsCompleted) { return }
        $timer.Stop()
        $output = @($script:worker.EndInvoke($script:pending))
        $payload = @($output | Where-Object { $null -ne $_.PSObject.Properties['ReportPath'] } | Select-Object -Last 1)
        # Some collectors emit handled access errors; the engine records those as manual review.
        if ($script:worker.InvocationStateInfo.State -eq 'Failed' -or $payload.Count -eq 0) {
            $messages = ($script:worker.Streams.Error | ForEach-Object { $_.ToString() }) -join '; '
            throw ('检查未完成。' + $messages)
        }
        $result = $payload[0]
        if (-not (Test-Path -LiteralPath $result.ReportPath -PathType Leaf)) { throw '未找到生成的报告。' }
        $script:allResults = @($result.Results)
        $script:lastReport = [string]$result.ReportPath
        $script:lastOutputDirectory = [string]$result.Directory
        Show-Results
        $counts = ($script:allResults | Group-Object 结果 | ForEach-Object {"$($_.Name) $($_.Count) 项"}) -join '   /   '
        $summary.Text = "检查完成 · $counts"
        Add-Log ('报告已保存：' + $script:lastReport)
        $statusLabel.Text = '检查完成 · 点击“打开完整报告”查看 HTML 报告，可在目录中找到 CSV 和 JSON。'
    } catch {
        $script:runError = $_.Exception.Message
        $summary.Text = '检查失败 · 请查看运行提示后重新检查'
        Add-Log $script:runError
    } finally {
        if ($null -ne $script:pending -and $script:pending.IsCompleted) {
            $timer.Stop()
            $script:worker.Dispose()
            $script:worker = $null
            $script:pending = $null
            Set-Running $false
            if ($null -ne $script:runError) { $progress.Value = 0 }
        }
    }
}

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 200
$timer.Add_Tick({ Update-Scan })
$start.Add_Click({ Start-Scan })
$filter.Add_SelectedIndexChanged({ Show-Results })
$grid.Add_SelectionChanged({ Show-Details })
$browse.Add_Click({
    $dialog = New-Object Windows.Forms.FolderBrowserDialog
    try {
        $dialog.Description = '选择检查报告的保存目录'
        if (Test-Path -LiteralPath $pathBox.Text -PathType Container) { $dialog.SelectedPath = $pathBox.Text }
        if ($dialog.ShowDialog($form) -eq 'OK') { $pathBox.Text = $dialog.SelectedPath }
    } finally { $dialog.Dispose() }
})
$report.Add_Click({
    try { Invoke-Item -LiteralPath $script:lastReport } catch { Add-Log ('无法打开报告：' + $_.Exception.Message) }
})
$folder.Add_Click({
    try { Invoke-Item -LiteralPath $script:lastOutputDirectory } catch { Add-Log ('无法打开目录：' + $_.Exception.Message) }
})
$form.Add_FormClosing({
    param($sender,$eventArgs)
    if ($null -ne $script:worker -and -not $script:closing) {
        # Let an active read finish without freezing the UI or abandoning the report writer.
        $eventArgs.Cancel = $true
        Add-Log '检查仍在运行，请等待完成后关闭窗口。'
    }
})

try {
    if ($SelfTest) {
        # Exercise the real controls and background worker without displaying a window.
        $optional.Checked = $true
        Start-Scan
        $watch = [Diagnostics.Stopwatch]::StartNew()
        while ($null -ne $script:worker -and $watch.Elapsed.TotalSeconds -lt 90) {
            Update-Scan
            [Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 50
        }
        if ($null -ne $script:worker) { throw 'Self-test timed out.' }
        if ($null -ne $script:runError) { throw $script:runError }
        if ($script:allResults.Count -ne 22 -or $grid.Rows.Count -ne 22) { throw 'Expected 22 result rows.' }
        if (@($script:allResults | Where-Object { $_.序号 -in 21,22 -and $_.结果 -eq '需人工复核' }).Count -ne 2) { throw 'Optional controls failed.' }
        $filter.SelectedIndex = 1
        if ($grid.Rows.Count -ne @($script:allResults | Where-Object { $_.结果 -eq '不合规' }).Count) { throw 'Result filter failed.' }
        $filter.SelectedIndex = 0
        if (-not $report.Enabled -or -not $folder.Enabled -or -not $start.Enabled) { throw 'Completion button state failed.' }
        if ($details.Text -notmatch '检查证据') { throw 'Details panel failed.' }
        $previousDirectory = $pathBox.Text
        $pathBox.Text = ''
        Start-Scan
        if ($null -eq $script:runError -or -not $start.Enabled) { throw 'Invalid path handling failed.' }
        $pathBox.Text = $previousDirectory
        $optional.Checked = $false
        Start-Scan
        $watch.Restart()
        while ($null -ne $script:worker -and $watch.Elapsed.TotalSeconds -lt 90) {
            Update-Scan
            [Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 50
        }
        if ($null -ne $script:worker -or $null -ne $script:runError) { throw 'Retry failed.' }
        if (@($script:allResults | Where-Object { $_.序号 -in 21,22 -and $_.结果 -eq '未启用' }).Count -ne 2) { throw 'Default optional state failed.' }
        if (-not [string]::IsNullOrWhiteSpace($PreviewPath)) {
            $form.PerformLayout()
            # Render the client panel off-screen; its parent form stays hidden.
            $form.Controls.Remove($layout)
            $layout.BackColor = $bg
            $layout.CreateControl()
            $layout.PerformLayout()
            $filter.SelectedIndex = 0
            $bitmap = New-Object Drawing.Bitmap($layout.Width,$layout.Height)
            try {
                $layout.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$layout.Width,$layout.Height)))
                $bitmap.Save([IO.Path]::GetFullPath($PreviewPath),[Drawing.Imaging.ImageFormat]::Png)
            } finally { $bitmap.Dispose(); $form.Controls.Add($layout) }
        }
        Write-Output 'PASS: background scan, 22 rows, optional on/off, filter, detail panel, report actions, invalid input and retry.'
        Write-Output $script:lastReport
    } else { [Windows.Forms.Application]::Run($form) }
} finally {
    $script:closing = $true
    $timer.Stop()
    $timer.Dispose()
    if ($null -ne $script:worker) { $script:worker.Stop(); $script:worker.Dispose() }
    $form.Dispose()
}
