param([Parameter(Mandatory)][string]$Out)
# Saves the Connect IQ simulator window to $Out without focusing it or sending input.
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class SimShot {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
$p = Get-Process simulator | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { throw "simulator is not running" }
$r = New-Object SimShot+RECT; [SimShot]::GetWindowRect($p.MainWindowHandle, [ref]$r) | Out-Null
$bmp = New-Object System.Drawing.Bitmap ($r.Right - $r.Left), ($r.Bottom - $r.Top)
$g = [System.Drawing.Graphics]::FromImage($bmp); $hdc = $g.GetHdc()
[SimShot]::PrintWindow($p.MainWindowHandle, $hdc, 2) | Out-Null   # 2 = PW_RENDERFULLCONTENT
$g.ReleaseHdc($hdc)
New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
$bmp.Save($Out)
