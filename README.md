# G-coordinator Docker Compose

G-coordinator GUI 版を Docker コンテナ内で起動するための構成です。

Phase 1 では、Linux ホスト上で X11 転送を使って GUI を表示します。

## 必要なもの

- Docker Engine と Docker Compose
- X11 または XWayland が使える Linux デスクトップ環境

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
UID=$(id -u) GID=$(id -g) docker compose run --rm gcoordinator
```

ホスト側の `./workspace` は、コンテナ内の `/workspace` にマウントされます。
G-code や作業ファイルの受け渡しに使えます。

## X11 アクセス許可を戻す

アプリケーションを終了した後、必要に応じて X server の許可を戻します。

```bash
xhost -local:docker
```

## 補足

- Docker イメージは `ubuntu:22.04` をベースにしています。
- G-coordinator はビルド時に upstream repository から clone されます。
- コンテナ内ではホストユーザーの UID/GID でアプリケーションを実行します。
- ホストの X11 認証ファイルがある場合は、起動スクリプトが `.Xauthority` をコンテナへ読み取り専用で渡します。
- GUI 表示を安定させるため、`QT_X11_NO_MITSHM=1` と `LIBGL_ALWAYS_SOFTWARE=1` を設定しています。
- Windows/macOS 対応は後続 Phase で追加予定です。
