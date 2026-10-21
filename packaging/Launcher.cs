using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

[assembly: AssemblyTitle("Windows 重点基线检查")]
[assembly: AssemblyDescription("本地 Windows 基线检查与报告")]
[assembly: AssemblyProduct("Windows 重点基线检查")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

internal static class Launcher
{
    // Quote a literal Windows process argument, including paths ending in backslashes.
    private static string Quote(string value)
    {
        var result = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in value)
        {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') result.Append('\\', slashes * 2 + 1);
            else result.Append('\\', slashes);
            result.Append(c);
            slashes = 0;
        }
        result.Append('\\', slashes * 2);
        return result.Append('"').ToString();
    }

    private static void Extract(string name, string directory)
    {
        using (Stream input = Assembly.GetExecutingAssembly().GetManifestResourceStream(name))
        {
            if (input == null) throw new InvalidOperationException("程序资源缺失：" + name);
            using (var output = new FileStream(Path.Combine(directory, name), FileMode.CreateNew, FileAccess.Write))
                input.CopyTo(output);
        }
    }

    [STAThread]
    private static int Main(string[] args)
    {
        bool selfTest = args.Length == 1 && args[0] == "--self-test";
        string baseDirectory = AppDomain.CurrentDomain.BaseDirectory;
        string runtime = Path.Combine(Path.GetTempPath(), "WindowsBaselineCheck-" + Guid.NewGuid().ToString("N"));
        string testLog = Path.Combine(baseDirectory, "exe-self-test.log");
        try
        {
            Directory.CreateDirectory(runtime);
            Extract("baseline-gui.ps1", runtime);
            Extract("baseline-check.ps1", runtime);
            string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                @"WindowsPowerShell\v1.0\powershell.exe");
            if (!File.Exists(powershell)) throw new FileNotFoundException("未找到 Windows PowerShell 5.1。", powershell);
            var start = new ProcessStartInfo(powershell);
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            start.WindowStyle = ProcessWindowStyle.Hidden;
            start.RedirectStandardOutput = true;
            start.RedirectStandardError = true;
            start.WorkingDirectory = baseDirectory;
            start.Arguments = "-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "
                + Quote(Path.Combine(runtime, "baseline-gui.ps1"))
                + " -DefaultOutputDirectory " + Quote(Path.Combine(baseDirectory, "reports"))
                + (selfTest ? " -SelfTest" : "");
            using (var process = Process.Start(start))
            {
                Task<string> output = process.StandardOutput.ReadToEndAsync();
                Task<string> error = process.StandardError.ReadToEndAsync();
                process.WaitForExit();
                Task.WaitAll(output, error);
                string messages = output.Result + Environment.NewLine + error.Result;
                if (selfTest) File.WriteAllText(testLog, messages, new UTF8Encoding(true));
                if (process.ExitCode != 0)
                {
                    if (!selfTest) MessageBox.Show("界面未能正常运行。\r\n\r\n" + messages,
                        "Windows 重点基线检查", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return process.ExitCode;
                }
                return 0;
            }
        }
        catch (Exception ex)
        {
            if (selfTest)
            {
                try { File.WriteAllText(testLog, ex.ToString(), new UTF8Encoding(true)); } catch { }
            }
            else MessageBox.Show("无法打开程序：\r\n" + ex.Message, "Windows 重点基线检查",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        finally
        {
            // Delete only this instance's two known resources; never recursively delete.
            foreach (string name in new[] { "baseline-gui.ps1", "baseline-check.ps1" })
            {
                try { File.Delete(Path.Combine(runtime, name)); } catch { }
            }
            try { Directory.Delete(runtime, false); } catch { }
        }
    }
}
