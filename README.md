# telnet-configurator: 基地局コンフィグ収集 (CBT) デモ

基地局装置に Telnet または SSH (パスワード認証 / 公開鍵認証) でログインし、コンフィギュレーションを収集する Perl プログラムです。
KDDI 様 PoC のデモ用に、実機の CBT と同じ構成（機種・ソフトウェアバージョンごとのスクリプト）を小さく再現しています。
デモでは Devin がこれを **Telnet から SSH (パスワード認証 / 公開鍵認証) に移行**します。台本は [docs/DEMO_SCENARIO.md](docs/DEMO_SCENARIO.md) を参照してください。

実機には接続できないため、**基地局シミュレータを自分のマシン (127.0.0.1) で動かして**収集・テストします。外部への接続は一切不要です。

## 構成

| パス | 役割 |
| --- | --- |
| `bin/cbt-collect` | 収集のエントリポイント。インベントリを読み、機種・SW バージョンごとのコレクタに振り分ける |
| `lib/CBT/Session.pm` | 装置セッション: ログイン、enable、コマンド実行。Telnet (Net::Telnet) と SSH (Net::OpenSSH の疑似端末上で同じプロンプト待ち処理) |
| `lib/CBT/Collector/*.pm` | 機種・SW バージョン別コレクタ (AX-4000 R5 / R6) |
| `collectors/bg7_v200.pl` | 共通ライブラリ以前からある単体スクリプト (BG-7 V200)。`CBT::Session` を使い Telnet / SSH に対応 |
| `conf/devices.conf` | 本番想定のインベントリ (例) |
| `conf/devices.local.conf` | ローカルシミュレータ向けインベントリ (Telnet) |
| `conf/devices.local-ssh.conf` | lab/ssh 向けインベントリ (SSH 公開鍵認証) |
| `conf/devices.local-docker.conf` | lab/docker 向けインベントリ (SSH パスワード認証 + 公開鍵認証) |
| `sim/` | 基地局シミュレータ (Perl コアモジュールのみ) |
| `lab/ssh/` | root も Docker も不要な SSH ラボ (公開鍵認証) |
| `lab/docker/` | Docker の SSH ラボ (パスワード認証 + 公開鍵認証) |
| `t/` | テスト (シミュレータを起動し、収集結果が装置の出力と一致するか検証。SSH ラボが起動していれば SSH も検証) |
| `scripts/demo_telnet_vs_ssh.sh` | Telnet と SSH の収集を左右に並べる比較デモ (動画も生成可能) |

### シミュレートする装置

| ホスト名 | 機種 / SW | 違い | Telnet | SSH (鍵, lab/ssh) | SSH (パスワード+鍵, lab/docker) |
| --- | --- | --- | --- | --- | --- |
| TKY-ENB-0001 | Hoshi Networks AX-4000 eNodeB / R5.2.1 | `enable` 必要、`terminal length 0` | 2301 | 2201 | 2401 |
| OSK-ENB-0102 | Hoshi Networks AX-4000 eNodeB / R6.1.0 | プロンプト `HOST[R6]#`、ページャ無効化が `terminal pager disable` に変更 | 2302 | 2202 | 2402 |
| NGY-GNB-0203 | Tsuki Systems BG-7 gNodeB / V200R003C10 | `login:` プロンプト、`<HOST>`、`screen-length 0 temporary` | 2303 | 2203 | 2403 |

認証情報 (ラボ専用): ユーザ `cbtadmin` / パスワード `cbt-pass` / enable パスワード `cbt-enable`。
ページャを無効にしないと出力は 20 行ごとに `--More--` で止まります (実機と同様)。
ベンダー名・機種名は架空です。

## セットアップ

Perl 5.16 以上。シミュレータはコアモジュールのみで動きます。コレクタには Net::Telnet、SSH には Net::OpenSSH と IO::Pty (と OpenSSH クライアント `ssh`) が必要です。

```sh
cpanm --installdeps .            # または: sudo apt install libnet-telnet-perl libnet-openssh-perl libio-pty-perl
                                 #        brew install cpanminus && cpanm --installdeps .
```

## 使い方 (Telnet)

```sh
make sim-start                   # 127.0.0.1:2301-2303 でシミュレータ起動
make collect                     # output/<装置名>/latest.cfg に収集
telnet 127.0.0.1 2301            # 手で触ることも可能 (cbtadmin / cbt-pass)
make sim-stop
make test                        # テスト (シミュレータは自動で起動・停止)
```

## SSH ラボ (自分のマシンに SSH 接続してテスト)

移行後の SSH 版をテストするための接続先です。どちらも 127.0.0.1 のみで待ち受けます。

**lab/ssh (公開鍵認証, root・Docker 不要)**: 自分のユーザ権限で専用の sshd を起動し、ポートごとに装置シミュレータを `ForceCommand` で割り当てます。ログインユーザは自分 (`$USER`)、鍵は `lab/.state/cbt_id_ed25519` (自動生成)。
root 以外で動く sshd はパスワードを検証できないため、パスワード認証は lab/docker を使います。

```sh
make lab-ssh-start
ssh -i lab/.state/cbt_id_ed25519 -p 2201 $USER@127.0.0.1
make lab-ssh-stop
```

**lab/docker (パスワード認証 + 公開鍵認証)**: コンテナ内の sshd で同じ装置を提供します。

```sh
make lab-docker-start
ssh -p 2401 cbtadmin@127.0.0.1                                   # パスワード: cbt-pass
ssh -i lab/.state/cbt_id_ed25519 -p 2401 cbtadmin@127.0.0.1      # 公開鍵
make lab-docker-stop
```

macOS の場合、lab/ssh は OS 同梱の `/usr/sbin/sshd` をそのまま使います (「リモートログイン」を有効にする必要はありません)。

## 使い方 (SSH)

インベントリの `protocol = ssh` の装置は SSH で収集します。SSH では認証を sshd が行うため、装置の `login:` / `Password:` プロンプト待ちは行わず、
シェルのプロンプトを待ってから enable・ページャ無効化・収集コマンドを Telnet と同じ手順で実行します (機種・SW ごとの違いはそのまま)。

```sh
make lab-ssh-start
make collect-ssh                 # = bin/cbt-collect -i conf/devices.local-ssh.conf   (公開鍵認証)

make lab-docker-start
make collect-docker              # = CBT_PASSWORD=... CBT_ENABLE_PASSWORD=... bin/cbt-collect -i conf/devices.local-docker.conf
                                 #   (TKY / NGY はパスワード認証、OSK は公開鍵認証)

bin/cbt-collect -v -i conf/devices.local-ssh.conf -d OSK-ENB-0102   # -v: 認証・enable・各コマンドの進捗を表示
```

Telnet と SSH は装置ごとに切り替えられるので、移行期間中は 1 つのインベントリに両方を混在させられます。

## インベントリのキー

```ini
[TKY-ENB-0001]
host = 10.0.0.1
protocol = ssh                      # telnet (デフォルト) | ssh
auth = key                          # password (デフォルト) | key
user = cbtadmin
key_file = ${CBT_KEY_FILE}          # 鍵パスも環境変数で渡す
known_hosts = /etc/cbt/known_hosts
host_key_check = yes                # yes (デフォルト) | accept-new
model = AX-4000
sw = R5.2.1
enable_password = ${CBT_ENABLE_PASSWORD}
```

| キー | 対象 | 説明 |
| --- | --- | --- |
| `host` | 共通 | 接続先 (必須) |
| `port` | 共通 | 省略時 Telnet 23 / SSH 22 |
| `protocol` | 共通 | `telnet` (デフォルト) または `ssh` |
| `user` | 共通 | ログインユーザ (必須) |
| `password` | Telnet / SSH `auth=password` | ログインパスワード |
| `enable_password` | 共通 | enable パスワード (AX-4000) |
| `model` / `sw` | 共通 | 機種・SW バージョン。コレクタの選択に使う (必須) |
| `auth` | SSH | `password` (デフォルト) または `key` |
| `key_file` | SSH `auth=key` | 秘密鍵ファイル (必須)。相対パスはリポジトリ直下から |
| `key_passphrase` | SSH `auth=key` | 鍵のパスフレーズ (任意) |
| `known_hosts` | SSH | ホスト鍵を照合・記録する known_hosts ファイル。省略時は ssh の既定 (`~/.ssh/known_hosts`) |
| `host_key_check` | SSH | `yes`: 未登録・不一致のホスト鍵は接続拒否 (本番向け)。`accept-new`: 未登録の鍵は初回に登録し、以後は不一致を拒否 (ラボ向け) |

- 値の中の `${NAME}` は環境変数に置き換えられます。パスワード・パスフレーズ・鍵パスはインベントリに直接書かず、環境変数で渡してください (未定義の変数は空文字になり、SSH パスワード認証で password が空ならエラー)。
- 誤ったキー (`protocol = rlogin` など)、Telnet 装置への SSH 専用キー、`auth=key` で `key_file` なし等はインベントリ読み込み時にエラーになります。
- ホスト鍵検証を無効にする設定 (`StrictHostKeyChecking=no` 相当) はサポートしていません。
- `collectors/bg7_v200.pl` にも同じ設定が `--protocol` `--auth` `--key-file` `--known-hosts` `--host-key-check` で渡されます。パスワードはコマンドライン引数ではなく環境変数で子プロセスに渡します。

## テスト

```sh
make test                        # Telnet のテストは常に実行
make lab-ssh-start && make test  # 公開鍵認証 (2201-2203) と Telnet/SSH の収集結果比較も実行
make lab-docker-start && make test   # パスワード認証 (2401-2403) も実行
```

SSH のテスト (`t/30_collect_ssh_key.t`, `t/31_collect_ssh_password.t`, `t/40_telnet_vs_ssh.t`) は対応するラボが起動していなければスキップします。
`t/40_telnet_vs_ssh.t` は Telnet と SSH の収集結果がヘッダの日時行 (`!! CBT collected ... at ...`) を除いて一致することを確認します。

## Telnet / SSH 比較デモ

tmux の左ペインで Telnet 版 (`conf/devices.local.conf`)、右ペインで SSH 版 (`conf/devices.local-ssh.conf`) の収集を同時に実行し、最後に両者の出力を diff します。
シミュレータと lab/ssh は必要なら自動で起動します。

```sh
make demo                                              # tmux で表示
scripts/demo_telnet_vs_ssh.sh --cast demo.cast         # asciinema のキャストに記録
scripts/demo_telnet_vs_ssh.sh --mp4 docs/demo/telnet_vs_ssh.mp4   # Xvfb + xterm + ffmpeg で MP4 録画 (キャストも出力)
```

録画済みの動画: [docs/demo/telnet_vs_ssh.mp4](docs/demo/telnet_vs_ssh.mp4) (キャスト: [docs/demo/telnet_vs_ssh.cast](docs/demo/telnet_vs_ssh.cast))
