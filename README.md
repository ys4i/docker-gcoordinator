# G-coordinator Docker Compose

G-coordinator GUI 版を Docker コンテナ内で起動するための構成です。

Linux、macOS、Windows のホストから Docker Compose で起動できます。

## 必要なもの

- Docker Engine と Docker Compose
- Linux の場合: X11 または XWayland が使えるデスクトップ環境
- macOS の場合: Docker Desktop
- Windows の場合: WSL2 Ubuntu と VcXsrv/X410、または WSLg

## ビルド

```bash
docker compose build
```

## Linux での起動

次の1コマンドで、リポジトリのインストール・更新、Docker EngineとComposeの
必要時のみのセットアップ、イメージ作成、起動まで実行します。

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ys4i/docker-gcoordinator/main/install-linux.sh)"
```

自動判定後は、未導入・更新あり・未ビルドなら`setup-linux.sh`を実行し、
導入・ビルド済みで更新がなければ`run-linux.sh`を実行します。
自動Docker導入はUbuntuとDebianに対応します。セットアップだけを行う場合:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ys4i/docker-gcoordinator/main/install-linux.sh)" -- --no-launch
```

リポジトリ内から直接起動する場合:

```bash
bash ./run-linux.sh
```

デバッグ用に一時的なログが必要な場合は、スクリプトの外側で `tee` にパイプします。

```bash
mkdir -p log
./run-linux.sh 2>&1 | tee "log/run-linux-$(date +%Y%m%d-%H%M%S).log"
```

この方法では画面に表示しながら、同じ内容を `log/` 配下にも保存できます。

手動で起動する場合は、以下の手順を実行します。

コンテナとファイルを共有するための `workspace` ディレクトリを作成します。

```bash
mkdir -p workspace
```

ローカルの Docker コンテナからホストの X server へ接続できるようにします。

```bash
xhost +local:docker
```

G-coordinator を起動します。

```bash
UID=$(id -u) GID=$(id -g) XAUTHORITY_PATH=${XAUTHORITY:-$HOME/.Xauthority} \
  docker compose -f docker-compose.yml -f docker-compose.linux.yml run --rm gcoordinator
```

ホスト側の `./workspace` は、コンテナ内の `/workspace` にマウントされます。
G-code や作業ファイルの受け渡しに使えます。

## X11 アクセス許可を戻す

アプリケーションを終了した後、必要に応じて X server の許可を戻します。

```bash
xhost -local:docker
```

## macOS での起動

Docker Desktopのインストール、Dockerイメージの作成、g-coordinatorの起動を
スクリプトで自動化できます。GUIはコンテナ内の仮想ディスプレイで描画し、
macOS標準の画面共有へVNC転送します。XQuartzは使用しません。

次の1コマンドで、インストール状態の判別、最新版への更新、Docker Desktopの
必要時のみのインストール、イメージ作成、起動まで実行できます。初回と2回目以降で
同じコマンドを使用します。

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ys4i/docker-gcoordinator/main/install-macos.sh)"
```

既定のインストール先は`~/Projects/docker-gcoordinator`です。既に正しい
リポジトリがある場合は`git pull --ff-only`で更新し、存在しない場合だけcloneします。
判定後は次の処理を自動的に選択します。

- 未インストール: clone後に`setup-macos.sh`を実行
- 更新あり、Docker Desktop未導入、またはDockerイメージ未作成:
  `setup-macos.sh`を実行
- 導入済みかつ更新なし: `run-macos.sh`を実行

セットアップだけを行って起動しない場合:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ys4i/docker-gcoordinator/main/install-macos.sh)" -- --no-launch
```

macOSのプライバシー保護により、Docker Desktopが`Downloads`配下のCompose
ファイルを読み取れない場合があります。ダウンロードしたプロジェクトは、実行前に
`~/Projects`などへ移動してください。

```bash
mkdir -p ~/Projects && mv ~/Downloads/docker-gcoordinator-main ~/Projects/
```

Finderから`start-gcoordinator-macos.command`をダブルクリックすると、
必要なセットアップ、Dockerイメージの作成、g-coordinatorの起動まで自動実行します。

```bash
bash ./setup-macos.sh
```

このコマンドも同様にセットアップから起動まで実行します。セットアップだけを行う場合:

```bash
bash ./setup-macos.sh --no-launch
```

`sh setup-macos.sh`のように`sh`を明示して実行しないでください。このスクリプトは
Bash用です。

Docker Desktopが未導入で、かつHomebrewも未導入の場合は、公式インストーラーを
使ってHomebrewを導入します。Docker Desktopが導入済みならHomebrewは不要です。
初回のみ、macOSのパスワード入力やDocker Desktopの利用規約確認を求められる
場合があります。画面の案内に従って完了してください。

Docker Desktopの起動後、次を実行すると、コンテナの準備完了後にmacOSの
画面共有が自動的に開きます。

```bash
bash ./run-macos.sh
```

Docker Desktopが停止している場合は、自動的に起動して利用可能になるまで待機します。
VNCはホストの`127.0.0.1`だけに公開され、`5900`から`5999`までの空きポートを
自動的に選択します。起動時に生成されたVNCパスワードはターミナルに表示され、
クリップボードにもコピーされます。画面共有のパスワード欄へ貼り付けてください。

ポートとパスワードを固定する場合:

```bash
MACOS_VNC_PORT=5901 MACOS_VNC_PASSWORD=gcoord01 bash ./run-macos.sh
```

次のエラーが表示された場合は、プロジェクトが`Downloads`配下にないことを確認します。

```text
open .../docker-compose.yml: operation not permitted
```

移動後のプロジェクトを1コマンドでセットアップして起動できます。

```bash
cd ~/Projects/docker-gcoordinator-main && bash ./setup-macos.sh
```

移動後もエラーが続く場合は、macOSの「システム設定」>
「プライバシーとセキュリティ」>「ファイルとフォルダ」で、使用しているターミナルと
Docker Desktopへのアクセスを許可してください。

## Windows での起動

Windows では WSL2 Ubuntu 内にインストールした Docker Engine を使います。
GUI 表示には VcXsrv または X410 などの Windows X server が必要です。

### 自動セットアップ

エクスプローラーから`start-gcoordinator.cmd`をダブルクリックすると、
導入状態を判定し、必要なセットアップまたはg-coordinatorの起動を自動実行します。

PowerShellでは、初回と2回目以降で同じ1コマンドを使用できます。

```powershell
& ([scriptblock]::Create((Invoke-RestMethod "https://raw.githubusercontent.com/ys4i/docker-gcoordinator/main/install-windows.ps1")))
```

このコマンドはリポジトリのインストール・更新状態と、モード別のビルド済み
リビジョンを確認します。未導入・更新あり・未ビルドなら`setup-windows.ps1`を、
導入・ビルド済みで更新がなければ`run-windows.ps1`を実行します。
初回セットアップでは、WSLユーザー設定、Docker EngineとVcXsrvの導入、
Dockerイメージの作成も行います。
Windows機能の有効化後にOS再起動が必須となる場合を除き、途中で同じコマンドを
再実行する必要はありません。再起動が必要な場合は再開処理が登録され、
Windowsへ再ログインした後にセットアップが自動的に続行されます。

セットアップだけを行って起動しない場合:

```powershell
& ([scriptblock]::Create((Invoke-RestMethod "https://raw.githubusercontent.com/ys4i/docker-gcoordinator/main/install-windows.ps1"))) -NoLaunch
```

リポジトリ内のスクリプトを直接実行する場合:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-windows.ps1 -Mode VcXsrv
```

セットアップはWSL2 Ubuntu内へDocker EngineとDocker Compose pluginを導入します。
WSLの既定ユーザーがrootの場合は、Windowsのユーザー名を基に一般ユーザーを作成して
既定ユーザーへ設定します。Docker導入処理はWSLのrootユーザーで実行し、
作成した一般ユーザーへ広範囲なパスワードなし管理者権限は付与しません。
Docker Desktopは使用しません。`winget` が使える環境ではVcXsrvの導入を試みます。
インストールを行わず確認とビルドだけ行う場合:

```powershell
.\setup-windows.ps1 -Mode VcXsrv -SkipInstall
```

### VcXsrv の起動例

VcXsrv の XLaunch で以下を選びます。

- `Multiple windows`
- `Start no client`
- `Disable access control`

環境によっては `Native opengl` を無効にした方が安定します。

### PowerShell から起動

PowerShell から WSLg 方式で起動する場合:

```powershell
.\run-windows.ps1
```

VcXsrv または X410 方式で起動する場合は、先に VcXsrv/X410 を起動してから以下を実行します。

```powershell
.\run-windows.ps1 -Mode VcXsrv
```

デバッグ用に一時的なログが必要な場合:

```powershell
New-Item -ItemType Directory -Force -Path log | Out-Null
.\run-windows.ps1 2>&1 | Tee-Object -FilePath "log\run-windows-$(Get-Date -Format yyyyMMdd-HHmmss).log"
```

手動で起動する場合はWSL内でWindowsホストのIPアドレスを`DISPLAY`へ設定します。

```bash
WINDOWS_HOST=$(ip route show default | awk '{ print $3; exit }')
export DISPLAY="${WINDOWS_HOST}:0.0"
UID=$(id -u) GID=$(id -g) \
  docker compose -f docker-compose.yml -f docker-compose.windows.yml run --rm gcoordinator
```

Windows では `/dev/dri` を使った GPU/DRI デバイス渡しは行いません。
`docker-compose.windows.yml` では `LIBGL_ALWAYS_SOFTWARE=1` を設定し、ソフトウェアレンダリングを使います。

## Windows WSLg での起動

Windows で GPU を使った描画を狙う場合は、VcXsrv ではなく WSLg 経由で起動します。
この手順は Windows PowerShell ではなく、WSL2 の Ubuntu などのシェル内で実行します。

### 自動セットアップ

PowerShell から前提確認とビルドを行う場合:

```powershell
& ([scriptblock]::Create((Invoke-RestMethod "https://raw.githubusercontent.com/ys4i/docker-gcoordinator/main/install-windows.ps1"))) -Mode WSLg
```

PowerShell の実行ポリシーで止まる場合:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-windows.ps1 -Mode WSLg
```

WSL 内でセットアップする場合:

```bash
./setup-wsl-docker.sh
./setup-wslg.sh
```

その後に起動します。

```bash
./run-wslg.sh
```

### 前提

- Windows 11、または WSLg 対応の Windows 10
- WSL2 distro
- WSLg が有効
- GPU vendor の WSL 対応ドライバ
- WSL内のDocker Engine（`setup-windows.ps1`で自動導入）

WSL 側で以下が存在することを確認します。

```bash
test -d /mnt/wslg && echo ok
test -e /dev/dxg && echo ok
test -d /usr/lib/wsl/lib && echo ok
```

### 起動

WSL のシェルで実行します。

```bash
./run-wslg.sh
```

デバッグ用に一時的なログが必要な場合:

```bash
mkdir -p log
./run-wslg.sh 2>&1 | tee "log/run-wslg-$(date +%Y%m%d-%H%M%S).log"
```

WSLg 方式では以下をコンテナへ渡します。

- `/mnt/wslg`
- `/dev/dxg`
- `/usr/lib/wsl`
- `DISPLAY`
- `WAYLAND_DISPLAY`
- `XDG_RUNTIME_DIR`
- `PULSE_SERVER`

`docker-compose.wslg.yml` では `LIBGL_ALWAYS_SOFTWARE=0` を設定し、WSLg の vGPU を使う構成にしています。

## 補足

- Docker イメージは `ubuntu:22.04` をベースにしています。
- G-coordinator はビルド時に upstream repository から clone されます。
- コンテナ内ではホストユーザーの UID/GID でアプリケーションを実行します。
- ホストの X11 認証ファイルがある場合は、起動スクリプトが `.Xauthority` をコンテナへ読み取り専用で渡します。
- 軽量化のため `LIBGL_ALWAYS_SOFTWARE=0` を設定し、`/dev/dri` がある Linux ホストでは起動スクリプトが GPU/DRI デバイスをコンテナへ渡します。
- `/dev/dri` がない環境では、GPU/DRI デバイスの受け渡しは行われません。
- Windows では X server 側の設定により GUI が表示されない場合があります。まず VcXsrv の `Disable access control` を確認してください。
- macOSではコンテナ内のXvfbへ描画し、localhost限定のVNC経由で画面共有を使用します。
- Windows で GPU 描画を使いたい場合は、PowerShell + VcXsrv ではなく WSLg 方式を使ってください。
- パスに日本語や空白が含まれる場所では、WindowsとWSL間のパス変換が不安定になる場合があります。
