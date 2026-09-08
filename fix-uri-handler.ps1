<# ============================================================
 obsidian:// リンクの飛び先を直すスクリプト

 なぜ要るか
   Obsidianは起動のたびに、自分を obsidian:// の処理役として
   登録し直す。そのとき --user-data-dir は付かない。
   複製した2つ目のObsidianが登録を取ると、リンクを踏んだときに
   「複製版のexeを、元のアカウントの設定で」起動してしまう。
   結果、タスクバーが点滅するだけで窓が出てこない。

 使い方
   powershell -NoProfile -ExecutionPolicy Bypass -File .\fix-uri-handler.ps1
     … 元から入っているObsidianへ戻す（既定）
   powershell -NoProfile -ExecutionPolicy Bypass -File .\fix-uri-handler.ps1 -Target copy -Id ai
     … 2つ目のObsidianへ向ける（そのプロファイル付きで正しく登録する）

 触るのは HKCU（自分のユーザー領域）だけ。管理者権限は要らない。
 どちらのObsidianも次に起動したとき、また自分に書き戻す。
 リンクが効かなくなったら、このスクリプトをもう一度実行する。
============================================================ #>

param(
  [ValidateSet('original','copy')]
  [string]$Target = 'original',
  [string]$Id,
  [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$logPath = Join-Path $PSScriptRoot 'fix-uri-handler-log.txt'
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

function Say($t) { Write-Host $t }

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
  return $null
}

$key = 'HKCU:\Software\Classes\obsidian\shell\open\command'

Say ''
Say '=============================================='
Say ' obsidian:// リンクの飛び先を直す'
Say '=============================================='
Say ''

if (Test-Path $key) {
  Say 'いまの設定:'
  Say ('  ' + (Get-ItemProperty $key).'(default)')
} else {
  Say 'いまの設定: 未登録'
}
Say ''

if ($Target -eq 'copy') {
  if (-not $Id) { $Id = Read-Host '2つ目のObsidianのID（例: ai）' }
  $Id = $Id -replace '[^A-Za-z0-9\-]', ''
  if ([string]::IsNullOrWhiteSpace($Id)) { throw 'IDが空です' }
  $exe  = Join-Path $env:LOCALAPPDATA "Obsidian-$Id\Obsidian.exe"
  $prof = Join-Path $env:APPDATA "obsidian-$Id"
  if (-not (Test-Path $exe))  { throw "2つ目のObsidianが見つかりません: $exe" }
  if (-not (Test-Path $prof)) { throw "設定フォルダが見つかりません: $prof" }
  $value = '"{0}" --user-data-dir="{1}" "%1"' -f $exe, $prof
  $what  = "2つ目のObsidian（$Id）"
} else {
  $exe = Find-ObsidianExe
  if (-not $exe) { throw '元から入っているObsidianが見つかりません' }
  $value = '"{0}" "%1"' -f $exe
  $what  = '元から入っているObsidian'
}

Say "これから $what へ向けます:"
Say "  $value"
Say ''
if (-not $Yes) {
  $go = Read-Host 'よければ Enter（やめるときは n）'
  if ($go -eq 'n') { Say '中止しました。'; try { Stop-Transcript | Out-Null } catch {}; exit }
}

if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
Set-ItemProperty -Path $key -Name '(default)' -Value $value

Say ''
Say '直しました。いまの設定:'
Say ('  ' + (Get-ItemProperty $key).'(default)')
Say ''
Say 'RESULT_URI_HANDLER=' + (Get-ItemProperty $key).'(default)'
Say ''
Say 'メモ: Obsidianは起動のたびに、この登録を自分に書き戻します。'
Say '      リンクが効かなくなったら、これをもう一度実行してください。'
Say ''
try { Stop-Transcript | Out-Null } catch {}
if (-not $Yes) { Read-Host '閉じるには Enter' }
