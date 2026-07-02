# G-coordinator Docker Compose

G-coordinator GUI 版を Docker コンテナ内で起動するための構成です。

Linux、macOS、Windows のホストから Docker Compose で起動できます。

## 必要なもの

- Docker Engine と Docker Compose
- Linux の場合: X11 または XWayland が使えるデスクトップ環境
- macOS の場合: Docker Desktop と XQuartz
- Windows の場合: WSL2 Ubuntu と VcXsrv/X410、または WSLg

## ビルド

```bash
docker compose build
```

## Linux での起動

起動スクリプトを使う場合:

```bash
./run-linux.sh
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

Docker Desktopと[XQuartz](https://www.xquartz.org/)のインストール、XQuartzの
`Allow connections from network clients`設定、両アプリケーションの起動を
次のスクリプトで自動化できます。

```bash
./setup-macos.sh
```

Homebrewが未導入の場合は、公式インストーラーを使ってHomebrewも導入します。
初回のみ、macOSのパスワード入力やDocker Desktopの利用規約確認を求められる
場合があります。画面の案内に従って完了してください。

手動でセットアップする場合は、Docker DesktopとXQuartzをインストールし、
XQuartzの `Settings` > `Security` で
`Allow connections from network clients`を有効にしてXQuartzを再起動します。

Docker Desktop と XQuartz の起動後、次を実行します。

```bash
./run-macos.sh
```

Docker Desktopが停止している場合は、起動して利用可能になるまで自動的に待機します。
スクリプトは必要な場合だけXQuartzへのアクセスを一時的に許可し、終了時に元へ戻します。
GUI接続には `host.docker.internal:0`、描画にはソフトウェアレンダリングを使用します。
別のディスプレイ番号が必要な場合は次のように指定できます。

```bash
MACOS_DISPLAY=host.docker.internal:1 ./run-macos.sh
```

手動で起動する場合:

```bash
/opt/X11/bin/xhost +localhost
mkdir -p workspace
UID=$(id -u) GID=$(id -g) MACOS_DISPLAY=host.docker.internal:0 \
  docker compose -f docker-compose.yml -f docker-compose.macos.yml run --rm gcoordinator
/opt/X11/bin/xhost -localhost
```

画面が表示されない場合は、XQuartzのネットワーククライアント許可を変更した後に
XQuartzを完全に終了して再起動したことを確認してください。

## Windows での起動

Windows では WSL2 Ubuntu 内にインストールした Docker Engine を使います。
GUI 表示には VcXsrv または X410 などの Windows X server が必要です。

### 自動セットアップ

PowerShell で以下を実行します。

```powershell
.\setup-windows.ps1 -Mode VcXsrv
```

PowerShell の実行ポリシーで `.ps1` の実行が止まる場合は、現在の PowerShell プロセスだけ一時的に許可します。

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\setup-windows.ps1 -Mode VcXsrv
```

ポリシーを変更せずに1回だけ実行する場合:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-windows.ps1 -Mode VcXsrv
```

セットアップ後にそのまま起動する場合:

```powershell
.\setup-windows.ps1 -Mode VcXsrv -Launch
```

セットアップはWSL2 Ubuntu内へDocker EngineとDocker Compose pluginを導入します。
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
WINDOWS_HOST=$(awk '/^nameserver / { print $2; exit }' /etc/resolv.conf)
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
.\setup-windows.ps1 -Mode WSLg
```

PowerShell の実行ポリシーで止まる場合:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-windows.ps1 -Mode WSLg
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
- macOSではXQuartzを設定変更後に再起動する必要があります。Docker DesktopのコンテナからはホストのUnixソケットを直接共有せず、`host.docker.internal`を使います。
- Windows で GPU 描画を使いたい場合は、PowerShell + VcXsrv ではなく WSLg 方式を使ってください。
- パスに日本語や空白が含まれる場所では、WindowsとWSL間のパス変換が不安定になる場合があります。
