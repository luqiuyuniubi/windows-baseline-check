# Windows 重点基线检查

Windows 本地基线检查工具，提供图形界面和单文件 EXE，根据 `20250627-重点基线检查项.xlsx` 整理 22 项检查。

## 直接使用

1. 下载仓库中的 [Windows基线检查.exe](./Windows基线检查.exe)（在文件页面点击 **Download raw file**）。
2. 双击打开；需要读取完整配置时，右键选择 **以管理员身份运行**。
3. 选择报告目录，点击 **开始检查**。完成后可筛选结果，查看检查证据和处理建议。

只需 EXE 即可运行，无需携带其他项目文件。适用于 Windows 10/11、Windows Server 2016 及以上，使用系统自带的 Windows PowerShell 5.1 和 .NET Framework。

## 功能

- 检查密码策略、账户锁定、屏保、审核策略、防火墙、防病毒软件、高危端口和远程软件。
- “敏感文件存储”和“浏览器密码保存”作为可选人工核查项目，默认不启用。
- 在界面查看结果、证据与建议，并导出 HTML、CSV、JSON 报告。
- 只读取配置，不修改系统设置，不读取或解密密码。

权限不足、读取失败或无法自动确认的项目会显示“需人工复核”。本地报告默认存入 EXE 同目录的 `reports`，已通过 `.gitignore` 排除；报告中可能包含计算机、账户和安全配置信息。

## 源码与构建

| 文件 | 用途 |
| --- | --- |
| `baseline-check.ps1` | 检查逻辑和报告生成 |
| `baseline-gui.ps1` | Windows 图形界面 |
| `packaging/Launcher.cs` | 单文件 EXE 启动程序 |
| `build-exe.ps1` | 使用系统编译器生成 EXE |
| `run-gui.bat` / `run-check.bat` | 直接运行脚本 |
| `20250627-重点基线检查项.xlsx` / `要求图片.png` | 检查依据与可选项参考 |

在项目目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build-exe.ps1
```

输出为 `Windows基线检查.exe`。也可直接双击 `run-gui.bat` 运行脚本界面。

完整操作和判断范围见 [使用说明](./使用说明.md)。
