# Claude Code 向けセットアップ手順

このファイルは **AIエージェント（Claude Code）が読んで実行する用**の手順書です。
人が手でやる場合は [README.md](README.md) を見てください。

対象OSは **Windows のみ**です。macOS / Linux では実行しないでください。

---

## ゴール

Obsidian をもう1つ増やし、**元のObsidianとは別アカウントでログインできる状態**にする。
タスクバーに2つ並び、アイコンの色で見分けられるようにする。

## 事前確認

```powershell
# Windows か
$env:OS
# Obsidian が入っているか（どれか1つでも見つかればOK。無ければ先に公式サイトからインストールが必要）
Test-Path "$env:LOCALAPPDATA\Obsidian\Obsidian.exe"
Test-Path "$env:LOCALAPPDATA\Programs\Obsidian\Obsidian.exe"
Test-Path "$env:USERPROFILE\Obsidian\Obsidian.exe"
Test-Path "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Obsidian.lnk"
```

Obsidian が入っていない場合はここで止めて、ユーザーに先にインストールしてもらってください。
インストール先の探索はスクリプト側でもやるので、ここで見つからなくても `Obsidian.lnk` があれば進めて構いません。

## 手順1: リポジトリを取得する

作業フォルダはユーザーに確認してください。指定がなければ `%USERPROFILE%\obsidian-multi-profile` で構いません。

```powershell
git clone https://github.com/tomita-anri/obsidian-multi-profile.git "$env:USERPROFILE\obsidian-multi-profile"
```

**git が入っていない場合**は、ZIPで取得してください（gitのインストールは不要です）。

```powershell
$zip = "$env:TEMP\omp.zip"
Invoke-WebRequest -Uri "https://codeload.github.com/tomita-anri/obsidian-multi-profile/zip/refs/heads/main" -OutFile $zip
Expand-Archive -Path $zip -DestinationPath "$env:TEMP\omp" -Force
Move-Item "$env:TEMP\omp\obsidian-multi-profile-main" "$env:USERPROFILE\obsidian-multi-profile" -Force
```

## 手順2: 設定値をユーザーに確認する

3つだけ決めます。ユーザーの指示に無ければ聞いてください。

| 項目 | 意味 | 例 |
|---|---|---|
| `-Label` | スタートメニューに出る名前 | `Obsidian（AI推進部）` |
| `-Id` | フォルダ名に使う**半角英数字**のID | `ai` |
| `-Color` | アイコンの色。`orange` / `teal` / `green` / `red` | `orange` |

`-Id` は半角英数字とハイフンのみです。日本語を入れないでください。
すでに同じ `-Id` で作ったものがある場合、上書き更新になります（設定・ログインは消えません）。

## 手順3: 実行する

**対話なしで一発で通ります。`-Yes` を必ず付けてください**（付けないと入力待ちで止まります）。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\obsidian-multi-profile\setup-obsidian-profile.ps1" -Label "Obsidian（AI推進部）" -Id ai -Color orange -Yes
```

本体を約300MBコピーするので、**1〜3分ほどかかります**。タイムアウトは長めに取ってください。

成功すると最後にこの4行が出ます。以降の確認はこの値を使ってください。

```
RESULT_APP_DIR=...      2つ目の本体フォルダ
RESULT_PROFILE_DIR=...  設定とログイン情報の置き場所
RESULT_SHORTCUT=...     作られたショートカット(.lnk)
RESULT_ICON=...         作られたアイコン(.ico)
```

## 手順4: 結果を確認する

```powershell
# ショートカットの中身が正しいか
$s = (New-Object -ComObject WScript.Shell).CreateShortcut("<RESULT_SHORTCUT>")
$s.TargetPath; $s.Arguments; $s.IconLocation
# 複製した exe の署名が壊れていないか（Valid でなければ異常）
(Get-AuthenticodeSignature "<RESULT_APP_DIR>\Obsidian.exe").Status
```

`Arguments` に `--user-data-dir="<RESULT_PROFILE_DIR>"` が入っていて、署名が `Valid` なら成功です。

## 手順5: ユーザーに頼むこと

ここから先は**自動化できません**。この3つを伝えて終わってください。

1. スタートメニューを開き、付けた名前（例: `Obsidian（AI推進部）`）を探す
2. 右クリック →「タスクバーにピン留めする」
   （Windowsの仕様上、ピン留めはスクリプトから作れません）
3. 起動して、2つ目のアカウントでログインし、使う保管庫を開く

あわせて **「同じ保管庫を2つのウィンドウで同時に開かないこと」** を必ず伝えてください。

## 手順6: `obsidian://` リンクについて伝える

**これは必ず伝えてください。作った時点では無害ですが、2つ目のObsidianを起動した瞬間に起きます。**

Obsidianは起動のたびに「`obsidian://` は自分が処理する」とWindowsへ登録し直します。このとき **`--user-data-dir` は付きません**。2つ目のObsidianがこの登録を取ると、リンクを踏んだときに「2つ目のexeを、1つ目のアカウントの設定で」起動してしまいます。

- 症状: リンクを踏むと**タスクバーが点滅するだけで窓が前に出てこない**
- 副作用: **1つ目のアカウント側の保管庫リストが書き換わることがある**
- 直しかた: 同じフォルダの `fix-links.bat`（または `fix-uri-handler.ps1`）

ユーザーが `obsidian://` リンクを使っているか分からない場合は、「ダッシュボードや他のアプリからObsidianのノートを直接開くリンクを使っていますか」と聞いてください。使っていなければ影響はありません。

非対話で直すときはこう実行します。

```powershell
# 元から入っているObsidianへ戻す（2つ目を入れる前と同じ状態）
powershell -NoProfile -ExecutionPolicy Bypass -File ".\fix-uri-handler.ps1" -Target original -Yes

# 2つ目のObsidianへ向ける（設定フォルダ付きで正しく登録する）
powershell -NoProfile -ExecutionPolicy Bypass -File ".\fix-uri-handler.ps1" -Target copy -Id ai -Yes
```

最後に `RESULT_URI_HANDLER=` の行が出るので、値を確認してください。

**Obsidianは起動のたびに書き戻すので、これは恒久的な設定ではありません。** 「リンクが効かなくなったら押し直す」ものだと伝えてください。

---

## やってはいけないこと

- **元から入っている Obsidian のフォルダ・設定（`%APPDATA%\obsidian`）に手を加えない。** このツールは複製側だけを触ります
- **exe にアイコンを埋め込まない。** 署名が壊れ、Smart App Control が有効なPCでは「Application Control policy にブロックされました」で起動しなくなります。アイコンはショートカット側に当てる設計です
- **ユーザーの保管庫（vault）のファイルを触らない。** このツールはアプリの複製だけを行います
- 消す作業（複製の削除・やり直し）は、必ずユーザーに確認してから行う

## うまくいかないとき

| 症状 | 原因と対応 |
|---|---|
| `Obsidian が見つかりませんでした` と出て止まる | Obsidian未インストール、または独自の場所にある。`Obsidian.exe` のフルパスをユーザーに聞いて、プロンプトに渡す |
| `コピーに失敗しました（robocopy コード 8以上）` | ディスク不足かファイルロック。空き容量（400MB以上）を確認し、2つ目のObsidianを終了してから再実行 |
| タスクバーのボタンが1つにまとまる | 複製先の exe から起動できていない。ショートカットの `TargetPath` が `RESULT_APP_DIR` 配下を指しているか確認する |
| アイコンが紫のまま | 先に古いアイコンでピン留めしている。**一度ピン留めを外し、スタートメニューから付け直す**よう伝える |
| ログインが1つ目と同じになる | `--user-data-dir` が渡っていない。ショートカットの `Arguments` を確認する。exe を直接ダブルクリックした場合もこうなる |
| 実行がブロックされる | `-ExecutionPolicy Bypass` を付けているか確認する |
| リンクを踏むとタスクバーが点滅するだけ | `obsidian://` の登録に `--user-data-dir` が無い。手順6の `fix-uri-handler.ps1` を実行する |

実行内容はスクリプトと同じ場所の `setup-log.txt` に全部残ります。原因が分からないときはこれを読んでください。
