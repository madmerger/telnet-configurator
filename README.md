# telnet-configurator: 基地局コンフィグ収集 (CBT) デモ

基地局装置に Telnet または SSH (パスワード認証 / 公開鍵認証) でログインし、コンフィギュレーションを収集する Perl プログラムです。
KDDI 様 PoC のデモ用に、実機の CBT と同じ構成（機種・ソフトウェアバージョンごとのスクリプト）を小さく再現しています。
デモでは Devin がこれを **Telnet から SSH (パスワード認証 / 公開鍵認証) に移行**します。台本は [docs/DEMO_SCENARIO.md](docs/DEMO_SCENARIO.md) を参照してください。

実機には接続できないため、**基地局シミュレータを自分のマシン (127.0.0.1) で動かして**収集・テストします。外部への接続は一切不要です。

## 構成

| パス | 役割 |
| --- | --- |
| `bin/cbt-collect` | 収集のエントリポイント。インベントリを読み、機種・SW バージョンごとのコレクタに振り分ける |
| `lib/CBT/Session.pm` | セッション: ログイン、enable、コマンド実行。Telnet は Net::Telnet、`protocol = ssh` は `CBT::Session::SSH` |
| `lib/CBT/Session/SSH.pm` | SSH セッション。OS の `ssh -tt` を使う (追加 CPAN モジュール不要)。パスワードは `libexec/cbt-askpass` 経由で渡す |
| `lib/CBT/Collector/*.pm` | 機種・SW バージョン別コレクタ (AX-4000 R5 / R6) |
| `collectors/bg7_v200.pl` | 共通ライブラリ以前からある単体スクリプト (BG-7 V200)。Telnet は Net::Telnet を直接、SSH は `CBT::Session::SSH` を使う |
| `conf/devices.conf` | 本番想定のインベントリ (例) |
| `conf/devices.local.conf` | ローカルシミュレータ向けインベントリ (Telnet) |
| `conf/devices.local-ssh.conf` | lab/ssh 向けインベントリ (SSH, 公開鍵) |
| `conf/devices.local-docker.conf` | lab/docker 向けインベントリ (SSH, 装置ごとにパスワード / 公開鍵) |
| `sim/` | 基地局シミュレータ (Perl コアモジュールのみ) |
| `lab/ssh/` | root も Docker も不要な SSH ラボ (公開鍵認証) |
| `lab/docker/` | Docker の SSH ラボ (パスワード認証 + 公開鍵認証) |
| `t/` | テスト (シミュレータを起動し、収集結果が装置の出力と一致するか検証) |

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

Perl 5.16 以上。シミュレータはコアモジュールのみで動きます。Telnet での収集には Net::Telnet、SSH での収集には OpenSSH クライアント 8.4 以上 (`ssh`) が必要です。

```sh
cpanm --installdeps .            # または: sudo apt install libnet-telnet-perl
                                 #        brew install cpanminus && cpanm Net::Telnet
```

## 使い方 (Telnet)

```sh
make sim-start                   # 127.0.0.1:2301-2303 でシミュレータ起動
make collect                     # output/<装置名>/latest.cfg に収集
telnet 127.0.0.1 2301            # 手で触ることも可能 (cbtadmin / cbt-pass)
make sim-stop
make test                        # テスト (シミュレータは自動で起動・停止)
```

## インベントリ: protocol と認証

装置ごとに `protocol` を選べます (省略時 `telnet`)。移行期間中は Telnet と SSH の装置を 1 つのインベントリに混在できます。

| キー | 値 | 説明 |
| --- | --- | --- |
| `protocol` | `telnet` / `ssh` | 省略時 `telnet` |
| `port` | | 省略時 23 (telnet) / 22 (ssh) |
| `auth` | `password` / `publickey` | SSH の認証方式。省略時は `key_file` があれば `publickey`、なければ `password` |
| `key_file` | パス | 公開鍵認証の秘密鍵。省略時 `$CBT_SSH_KEY_FILE` |
| `known_hosts` | パス | 省略時 `$CBT_SSH_KNOWN_HOSTS`、それもなければ ssh の既定 (`~/.ssh/known_hosts`) |
| `host_key_check` | `yes` / `accept-new` / `no` | ssh の `StrictHostKeyChecking`。省略時 `yes` (本番想定)。ラボは `accept-new` |
| `password` | | 省略時 `$CBT_PASSWORD`。SSH では `SSH_ASKPASS` 経由で ssh に渡し、コマンドラインには出さない |
| `enable_password` | | 省略時 `$CBT_ENABLE_PASSWORD` |

値には `${NAME}` で環境変数を書けます。空の値・未定義の環境変数は「未指定」として扱い、上の環境変数にフォールバックします。
SSH では sshd が認証するため、ログインプロンプトは無く装置のプロンプトから始まります (enable やページャ無効化は Telnet と同じ)。
セッションログ (`log/<装置名>.session.log`) ではパスワードを `********` に置き換えます。

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

### SSH で収集・テスト

```sh
make lab-ssh-start && make collect-ssh          # 公開鍵 (lab/ssh)
make lab-docker-start && make collect-docker    # パスワード + 公開鍵 (lab/docker)
make test                                       # 起動中のラボに対して SSH のテストも実行 (未起動のラボはスキップ)
```

`t/30_collect_ssh.t` は、各ラボ・各認証方式で収集結果が装置の出力と一致することに加え、Net::Telnet がある環境では Telnet で収集した結果と SSH の結果が一致すること (移行前後の比較) と、Telnet / SSH 混在インベントリを確認します。
