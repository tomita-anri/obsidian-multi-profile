<# ============================================================
 Obsidian をもう1つ増やして、別アカウントで使えるようにするスクリプト

 やること
   1. すでに入っている Obsidian の場所を自動で探す
   2. その本体フォルダを %LOCALAPPDATA%\Obsidian-<ID> に複製する
   3. 設定フォルダ（ログイン情報の置き場所）を別に用意する
   4. 元のロゴの色だけ変えたアイコンを作る
   5. スタートメニューにショートカットを作る

 元から入っている Obsidian には一切手を加えません。
 やり直したいときは、このスクリプトをもう一度実行してください。

 使い方は2通り
   ・そのまま実行  … 質問に答えていく（start-here.bat をダブルクリックした場合）
   ・引数で一発実行 … AIエージェントなどから叩く場合
       powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-obsidian-profile.ps1 `
         -Label "Obsidian（AI推進部）" -Id ai -Color orange -Yes
============================================================ #>

param(
  # スタートメニューに出す名前
  [string]$Label,
  # フォルダにつける英数字のID（半角）
  [string]$Id,
  # アイコンの色
  [ValidateSet('orange','teal','green','red')]
  [string]$Color,
  # 確認と最後のEnter待ちを省く（対話なしで走らせるとき）
  [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$logPath = Join-Path $PSScriptRoot 'setup-log.txt'
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

function Say($t) { Write-Host $t }
function Ask($t, $def) {
  $v = Read-Host "$t [$def]"
  if ([string]::IsNullOrWhiteSpace($v)) { return $def }
  return $v.Trim()
}

# ---- ネイティブ API（アイコンの取り出し・色替え用） ----
$code = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

public static class ObsIcon {
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern IntPtr LoadLibraryEx(string f, IntPtr h, uint flags);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool FreeLibrary(IntPtr h);
  public delegate bool EnumResNameProc(IntPtr hModule, IntPtr lpszType, IntPtr lpszName, IntPtr lParam);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool EnumResourceNames(IntPtr hModule, IntPtr lpszType, EnumResNameProc cb, IntPtr lParam);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern IntPtr FindResource(IntPtr hModule, IntPtr lpName, IntPtr lpType);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern IntPtr LoadResource(IntPtr hModule, IntPtr hResInfo);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern IntPtr LockResource(IntPtr hResData);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern uint SizeofResource(IntPtr hModule, IntPtr hResInfo);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)]
  public static extern int PrivateExtractIcons(string f, int idx, int cx, int cy, IntPtr[] ph, int[] pid, int n, int flags);
  [DllImport("user32.dll")]
  public static extern bool DestroyIcon(IntPtr h);

  // exe の中にある一番大きい PNG アイコンを取り出す。無ければ 256px で描き出す。
  public static Bitmap LoadBaseIcon(string exe) {
    IntPtr h = LoadLibraryEx(exe, IntPtr.Zero, 0x2);
    byte[] best = null;
    if (h != IntPtr.Zero) {
      List<IntPtr> names = new List<IntPtr>();
      EnumResourceNames(h, (IntPtr)3,
        delegate(IntPtr m, IntPtr t, IntPtr n, IntPtr l) { names.Add(n); return true; }, IntPtr.Zero);
      foreach (IntPtr n in names) {
        IntPtr fi = FindResource(h, n, (IntPtr)3);
        if (fi == IntPtr.Zero) continue;
        uint sz = SizeofResource(h, fi);
        IntPtr p = LockResource(LoadResource(h, fi));
        if (p == IntPtr.Zero || sz < 8) continue;
        byte[] b = new byte[sz];
        Marshal.Copy(p, b, 0, (int)sz);
        if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
          if (best == null || b.Length > best.Length) best = b;
        }
      }
      FreeLibrary(h);
    }
    if (best != null) {
      using (MemoryStream ms = new MemoryStream(best)) {
        using (Bitmap tmp = (Bitmap)Bitmap.FromStream(ms)) { return new Bitmap(tmp); }
      }
    }
    IntPtr[] hh = new IntPtr[1]; int[] ids = new int[1];
    int cnt = PrivateExtractIcons(exe, 0, 256, 256, hh, ids, 1, 0);
    if (cnt < 1 || hh[0] == IntPtr.Zero) throw new Exception("アイコンを取り出せませんでした: " + exe);
    Bitmap outBmp;
    using (Icon ic = Icon.FromHandle(hh[0])) { outBmp = ic.ToBitmap(); }
    DestroyIcon(hh[0]);
    return outBmp;
  }

  public static Bitmap Recolor(Bitmap src, double hueShift, double satScale) {
    Bitmap dst = new Bitmap(src.Width, src.Height, PixelFormat.Format32bppArgb);
    for (int y = 0; y < src.Height; y++) {
      for (int x = 0; x < src.Width; x++) {
        Color c = src.GetPixel(x, y);
        if (c.A == 0) { dst.SetPixel(x, y, Color.FromArgb(0,0,0,0)); continue; }
        double hh = c.GetHue() + hueShift;
        while (hh >= 360) hh -= 360;
        while (hh < 0) hh += 360;
        double ss = Math.Min(1.0, c.GetSaturation() * satScale);
        dst.SetPixel(x, y, FromHsl(hh, ss, c.GetBrightness(), c.A));
      }
    }
    return dst;
  }

  static Color FromHsl(double h, double s, double l, int a) {
    double cc = (1 - Math.Abs(2*l - 1)) * s;
    double hp = h / 60.0;
    double xx = cc * (1 - Math.Abs(hp % 2 - 1));
    double r=0,g=0,b=0;
    if (hp < 1) { r=cc; g=xx; b=0; }
    else if (hp < 2) { r=xx; g=cc; b=0; }
    else if (hp < 3) { r=0; g=cc; b=xx; }
    else if (hp < 4) { r=0; g=xx; b=cc; }
    else if (hp < 5) { r=xx; g=0; b=cc; }
    else { r=cc; g=0; b=xx; }
    double m = l - cc/2;
    int R = (int)Math.Round(Math.Max(0, Math.Min(255, (r+m)*255)));
    int G = (int)Math.Round(Math.Max(0, Math.Min(255, (g+m)*255)));
    int B = (int)Math.Round(Math.Max(0, Math.Min(255, (b+m)*255)));
    return Color.FromArgb(a, R, G, B);
  }

  public static Bitmap Resize(Bitmap src, int size) {
    Bitmap b = new Bitmap(size, size, PixelFormat.Format32bppArgb);
    using (Graphics g = Graphics.FromImage(b)) {
      g.CompositingMode = CompositingMode.SourceCopy;
      g.InterpolationMode = InterpolationMode.HighQualityBicubic;
      g.PixelOffsetMode = PixelOffsetMode.HighQuality;
      g.SmoothingMode = SmoothingMode.HighQuality;
      g.DrawImage(src, 0, 0, size, size);
    }
    return b;
  }

  public static byte[] ToPng(Bitmap b) {
    using (MemoryStream ms = new MemoryStream()) { b.Save(ms, ImageFormat.Png); return ms.ToArray(); }
  }

  public static byte[] ToDib(Bitmap b) {
    int w = b.Width, h = b.Height;
    int maskRow = ((w + 31) / 32) * 4;
    int xorSize = w * h * 4;
    byte[] o = new byte[40 + xorSize + maskRow * h];
    BitConverter.GetBytes(40).CopyTo(o, 0);
    BitConverter.GetBytes(w).CopyTo(o, 4);
    BitConverter.GetBytes(h * 2).CopyTo(o, 8);
    BitConverter.GetBytes((short)1).CopyTo(o, 12);
    BitConverter.GetBytes((short)32).CopyTo(o, 14);
    BitConverter.GetBytes(0).CopyTo(o, 16);
    BitConverter.GetBytes(xorSize).CopyTo(o, 20);
    int p = 40;
    for (int y = h - 1; y >= 0; y--) {
      for (int x = 0; x < w; x++) {
        Color c = b.GetPixel(x, y);
        o[p++] = c.B; o[p++] = c.G; o[p++] = c.R; o[p++] = c.A;
      }
    }
    return o;
  }

  public static void WriteIco(Bitmap src, string outPath) {
    int[] sizes = new int[] { 16, 20, 24, 32, 40, 48, 64 };
    List<byte[]> datas = new List<byte[]>();
    List<int> dims = new List<int>();
    foreach (int s in sizes) {
      using (Bitmap b = Resize(src, s)) { datas.Add(ToDib(b)); dims.Add(s); }
    }
    using (Bitmap b256 = Resize(src, 256)) { datas.Add(ToPng(b256)); dims.Add(256); }
    using (MemoryStream ms = new MemoryStream()) {
      BinaryWriter bw = new BinaryWriter(ms);
      bw.Write((ushort)0); bw.Write((ushort)1); bw.Write((ushort)datas.Count);
      int offset = 6 + 16 * datas.Count;
      for (int i = 0; i < datas.Count; i++) {
        byte dim = dims[i] >= 256 ? (byte)0 : (byte)dims[i];
        bw.Write(dim); bw.Write(dim); bw.Write((byte)0); bw.Write((byte)0);
        bw.Write((ushort)1); bw.Write((ushort)32);
        bw.Write((uint)datas[i].Length); bw.Write((uint)offset);
        offset += datas[i].Length;
      }
      foreach (byte[] d in datas) bw.Write(d);
      bw.Flush();
      File.WriteAllBytes(outPath, ms.ToArray());
    }
  }
}
'@
Add-Type -TypeDefinition $code -ReferencedAssemblies System.Drawing

# ---- 1. Obsidian の場所を探す ----
function Find-ObsidianExe {
  $cands = @()
  $lnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Obsidian.lnk'
  if (Test-Path $lnk) {
    try { $cands += (New-Object -ComObject WScript.Shell).CreateShortcut($lnk).TargetPath } catch {}
  }
  $cands += Join-Path $env:LOCALAPPDATA 'Obsidian\Obsidian.exe'
  $cands += Join-Path $env:LOCALAPPDATA 'Programs\Obsidian\Obsidian.exe'
  $cands += Join-Path $env:USERPROFILE 'Obsidian\Obsidian.exe'
  $cands += Join-Path $env:ProgramFiles 'Obsidian\Obsidian.exe'
  foreach ($p in $cands) {
    if ($p -and (Test-Path $p) -and ((Split-Path $p -Leaf) -eq 'Obsidian.exe')) { return $p }
  }
  $keys = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )
  foreach ($k in $keys) {
    $items = Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*Obsidian*' }
    foreach ($i in $items) {
      if ($i.InstallLocation) {
        $p = Join-Path $i.InstallLocation 'Obsidian.exe'
        if (Test-Path $p) { return $p }
      }
    }
  }
  return $null
}

Say ''
Say '=============================================='
Say ' Obsidian をもう1つ増やす（別アカウント用）'
Say '=============================================='
Say ''

$srcExe = Find-ObsidianExe
if (-not $srcExe) {
  Say 'Obsidian が見つかりませんでした。'
  $srcExe = Read-Host 'Obsidian.exe のフルパスを貼り付けてください'
  if (-not (Test-Path $srcExe)) { throw "見つかりません: $srcExe" }
}
$srcDir = Split-Path $srcExe -Parent
Say "見つかった Obsidian : $srcDir"
Say ''

# ---- 2. 名前・ID・色を決める（引数で渡されていれば聞かない） ----
if ($Label) {
  $label = $Label
} else {
  $label = Ask '2つ目のObsidianの名前（スタートメニューに出る名前）' 'Obsidian（サブ）'
}
$label = ($label -replace '[\\/:*?"<>|]', '').Trim()
if ([string]::IsNullOrWhiteSpace($label)) { throw '名前が空です' }

if ($Id) {
  $slug = $Id -replace '[^A-Za-z0-9\-]', ''
  if ([string]::IsNullOrWhiteSpace($slug)) { throw 'IDは半角英数字で指定してください' }
} else {
  do {
    $slug = Ask 'フォルダにつける英数字のID（半角、記号なし）' 'sub'
    $slug = $slug -replace '[^A-Za-z0-9\-]', ''
  } while ([string]::IsNullOrWhiteSpace($slug))
}

if ($Color) {
  $colorKey = $Color
} else {
  Say ''
  Say 'アイコンの色を選んでください（元のロゴの色だけ変えます）'
  Say '  1) オレンジ'
  Say '  2) 水色'
  Say '  3) グリーン'
  Say '  4) レッド'
  $colorNo = Ask '番号' '1'
  switch ($colorNo) {
    '2'     { $colorKey = 'teal' }
    '3'     { $colorKey = 'green' }
    '4'     { $colorKey = 'red' }
    default { $colorKey = 'orange' }
  }
}
switch ($colorKey) {
  'teal'  { $hue = 275; $sat = 1.0 }
  'green' { $hue = 200; $sat = 1.0 }
  'red'   { $hue =  90; $sat = 1.1 }
  default { $hue = 118; $sat = 1.2 }
}

$dstDir  = Join-Path $env:LOCALAPPDATA "Obsidian-$slug"
$profDir = Join-Path $env:APPDATA "obsidian-$slug"
$icoPath = Join-Path $profDir 'obsidian-icon.ico'
$lnkPath = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$label.lnk"

Say ''
Say '--- この内容で作ります ---'
Say "  本体の複製先  : $dstDir"
Say "  設定の置き場所: $profDir"
Say "  ショートカット: $label"
Say ''
if (-not $Yes) {
  $go = Ask 'よければ Enter（やめるときは n）' 'y'
  if ($go -eq 'n') { Say '中止しました。'; try { Stop-Transcript | Out-Null } catch {}; exit }
}

# ---- 3. 複製先が起動中なら止める ----
$running = Get-Process Obsidian -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$dstDir\*" }
if ($running) {
  Say '複製先の Obsidian が起動中なので終了します。'
  $running | Stop-Process -Force
  Start-Sleep -Seconds 3
}

# ---- 4. 本体を複製 ----
Say ''
Say '本体をコピーしています（300MBほどあるので少し待ちます）...'
$null = robocopy $srcDir $dstDir /MIR /NFL /NDL /NJH /NJS /NP
if ($LASTEXITCODE -ge 8) { throw "コピーに失敗しました（robocopy コード $LASTEXITCODE）" }
$unins = Join-Path $dstDir 'Uninstall Obsidian.exe'
if (Test-Path $unins) { Rename-Item $unins 'Uninstall Obsidian.exe.disabled' -Force }
Say 'コピー完了。'

# ---- 5. 設定フォルダとアイコン ----
if (-not (Test-Path $profDir)) { New-Item -ItemType Directory -Path $profDir | Out-Null }
Say 'アイコンを作っています...'
$base = [ObsIcon]::LoadBaseIcon($srcExe)
$rec  = [ObsIcon]::Recolor($base, $hue, $sat)
[ObsIcon]::WriteIco($rec, $icoPath)
Say "アイコン: $icoPath"

# ---- 6. ショートカット ----
$sh = New-Object -ComObject WScript.Shell
$sc = $sh.CreateShortcut($lnkPath)
$sc.TargetPath       = Join-Path $dstDir 'Obsidian.exe'
$sc.Arguments        = '--user-data-dir="' + $profDir + '"'
$sc.WorkingDirectory = $dstDir
$sc.IconLocation     = "$icoPath,0"
$sc.Description      = "$label （別アカウント用のObsidian）"
$sc.Save()
Say "ショートカット: $lnkPath"

try { Start-Process 'ie4uinit.exe' -ArgumentList '-show' -WindowStyle Hidden } catch {}

Say ''
Say '=============================================='
Say ' 完了しました'
Say '=============================================='
Say ''
Say '次にやること:'
Say "  1. スタートメニューを開いて「$label」を探す"
Say '  2. 右クリック →「タスクバーにピン留めする」'
Say '     （ピン留めはWindowsの仕様で自動化できません）'
Say '  3. 起動して、2つ目のアカウントでログインする'
Say ''
Say '注意:'
Say '  ・元から入っている Obsidian はそのままです'
Say '  ・同じ保管庫を2つのウィンドウで同時に開かないでください'
Say '  ・Obsidian本体を更新したら、このスクリプトをもう一度実行すると'
Say '    2つ目も同じバージョンになります（設定・ログインは消えません）'
Say ''
Say '--- 結果（この行はAIエージェント用の要約です） ---'
Say "RESULT_APP_DIR=$dstDir"
Say "RESULT_PROFILE_DIR=$profDir"
Say "RESULT_SHORTCUT=$lnkPath"
Say "RESULT_ICON=$icoPath"
Say ''
try { Stop-Transcript | Out-Null } catch {}
if (-not $Yes) { Read-Host '閉じるには Enter' }
