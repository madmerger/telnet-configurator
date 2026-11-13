# telnet-configurator: 基地局コンフィグ収集 (CBT) デモ

基地局装置に Telnet でログインし、コンフィギュレーションを収集する Perl プログラムです。
KDDI 様 PoC のデモ用に、実機の CBT と同じ構成（機種・ソフトウェアバージョンごとのスクリプト）を小さく再現しています。
デモでは Devin がこれを **Telnet から SSH (パスワード認証 / 公開鍵認証) に移行**します。台本は [docs/DEMO_SCENARIO.md](docs/DEMO_SCENARIO.md) を参照してください。

実機には接続できないため、**基地局シミュレータを自分のマシン (127.0.0.1) で動かして**収集・テストします。外部への接続は一切不要です。

## 構成

| パス | 役割 |
| --- | --- |
| `bin/cbt-collect` | 収集のエントリポイント。インベントリを読み、機種・SW バージョンごとのコレクタに振り分ける |
| `lib/CBT/Session.pm` | Telnet セッション (Net::Telnet): ログイン、enable、コマンド実行 |
| `lib/CBT/Collector/*.pm` | 機種・SW バージョン別コレクタ (AX-4000 R5 / R6) |
| `collectors/bg7_v200.pl` | 共通ライブラリ以前からある単体スクリプト (BG-7 V200)。Net::Telnet を直接使う |
| `conf/devices.conf` | 本番想定のインベントリ (例) |
| `conf/devices.local.conf` | ローカルシミュレータ向けインベントリ |
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

Perl 5.16 以上。シミュレータはコアモジュールのみで動きます。コレクタには Net::Telnet が必要です。

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

## SSH で収集する (ブランチ demo/ssh-reference の参考実装)

インベントリの装置ごとに `protocol = ssh` と認証方式を指定します (Telnet の装置と混在可)。

```ini
[TKY-ENB-0001]
host = 10.10.1.21
protocol = ssh                     # telnet (既定) | ssh。port の既定は 23 / 22
auth = password                    # password | key
user = cbtadmin
password = ${CBT_PASSWORD}
known_hosts = /etc/cbt/known_hosts # 任意
model = AX-4000
sw = R5.2.1
enable_password = ${CBT_ENABLE_PASSWORD}
```

公開鍵認証は `auth = key` と `key_file = <秘密鍵のパス>`。相対パスはリポジトリのルートから解決します。

```sh
make lab-ssh-start && make collect-ssh          # lab/ssh (公開鍵)
make lab-docker-start && make collect-docker    # lab/docker (パスワード + 公開鍵)
make test                                       # 起動中の SSH ラボがあれば SSH のテストも実行
```
