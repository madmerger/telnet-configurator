# デモ台本: Perl の CBT を Telnet から SSH へ移行する

所要時間の目安: 15〜20 分 (Devin の作業時間を含む)。

## 伝えたいこと

1. 機種・ソフトウェアバージョンごとに散らばった古い Perl スクリプトでも、Devin はコードを読んで「どこで Telnet を使っているか」を全部洗い出せる。
2. 実機に届かない環境でも、Devin は自分のマシン上にテスト環境 (シミュレータ + sshd) を用意して、移行前後で収集結果が変わらないことを確かめてから PR を出す。
3. パスワード認証と公開鍵認証の両方、機種ごとの差分 (プロンプト、ページャ、enable) を保ったまま移行できる。数百本のスクリプトにも同じ手順を横展開できる。

## 事前準備 (デモ前日まで)

- このリポジトリを Devin から clone / push できる状態にしておく。
- 手元で一度 `make sim-start && make collect && make test` が通ることを確認。
- Docker が使えるなら `make lab-docker-start` を一度実行してイメージをビルドしておく (当日のビルド待ちを避ける)。
- 万一に備え、移行後の参考実装をブランチ `demo/ssh-reference` に置いてある (後述「バックアッププラン」)。

## シーン 1: 現状を見せる (3 分)

画面: ターミナル + エディタ

1. 構成を説明する。「CBT は機種と SW バージョンごとに Perl スクリプトがある」
   - `lib/CBT/Collector/AX4000_R5.pm` と `AX4000_R6.pm`: 同じ機種でも R6 でプロンプトとページャのコマンドが違う
   - `collectors/bg7_v200.pl`: 共通ライブラリを使わず、Net::Telnet を直接呼ぶ古いスクリプト (実際の CBT にもよくあるパターン)
2. シミュレータを起動して収集する。
   ```sh
   make sim-start
   make collect
   cat output/TKY-ENB-0001/latest.cfg
   ```
3. (任意・効果大) Telnet はパスワードが平文で流れることを見せる。
   ```sh
   sudo tcpdump -i lo -A -s0 'tcp port 2301' | grep -a -A1 -i password    # macOS は -i lo0
   ```
   別ターミナルで `make collect` を実行すると `cbt-pass` がそのまま見える。「だから SSH に移行したい」

話すポイント: 「実機はファイアウォールの向こうにあって、開発環境からは触れない。だからシミュレータを自分のマシンで動かしている。Devin も同じものを使ってテストする」

## シーン 2: Devin に依頼する (1 分)

Devin のセッションを開き、以下をそのまま貼る (日本語のままで可)。

> madmerger/telnet-configurator の CBT コンフィグ収集プログラムを、Telnet から SSH に移行してください。
>
> - 全機種 (AX-4000 R5 / R6、BG-7 V200) を SSH で収集できるようにする。`collectors/` の単体スクリプトも対象。
> - 認証はパスワード認証と公開鍵認証の両方に対応し、装置ごとにインベントリで選べるようにする。
> - 移行期間中は Telnet も使えるように、装置ごとに protocol を切り替えられるようにする。
> - パスワードや鍵のパスはインベントリに直接書かず、環境変数でも渡せるようにする。
> - 実機には接続できないので、README の SSH ラボ (lab/ssh: 公開鍵、lab/docker: パスワード + 公開鍵) に自分のマシンから接続してテストする。
> - 既存の Telnet のテストは通したまま、SSH (パスワード / 公開鍵) のテストを追加する。移行前後で収集結果が同じであることを確認する。
> - 完了したら PR を作成し、変更点とテスト結果をまとめる。

## シーン 3: Devin の作業を見せる (8〜12 分、要所だけ解説)

期待される流れと、そのとき話すこと:

| Devin の動き | 話すポイント |
| --- | --- |
| リポジトリを読み、`grep Net::Telnet` などで Telnet 依存箇所を洗い出す (`lib/CBT/Session.pm` と `collectors/bg7_v200.pl` の 2 か所、プロンプトやログイン処理の前提は各コレクタ) | 人が見落としがちな単体スクリプトも拾う。数百本あっても同じ |
| 方針を立てる (例: Net::OpenSSH で接続し、取得した疑似端末の上で既存の Net::Telnet のプロンプト処理を再利用する) | 既存ロジックを活かす最小の変更。機種ごとの差分は壊さない |
| `make test` で現状のテストが通ることを確認 | 変更前の基準を取る |
| `make lab-ssh-start` / `make lab-docker-start` で SSH ラボを起動し、手で `ssh` してプロンプトを確認 | 外部に出ず、自分のマシンだけでテスト環境を作る |
| 実装: インベントリに `protocol` / `auth` / `key_file` を追加、SSH ではログインプロンプトが無いことへの対応、BG-7 単体スクリプトの移行 | SSH では認証が sshd 側で終わるので、ログイン処理が変わる |
| SSH 用インベントリ (`conf/devices.local-ssh.conf` など) とテストを追加し、Telnet と SSH の収集結果を比較 | 移行前後で収集結果が一致することを機械的に確認 |
| PR 作成 | レビュー可能な単位で出てくる |

待ち時間に話すこと:
- 実際の CBT では機種・SW バージョンの組み合わせが多い。1 本目を人と Devin で作り込み、それを手本 (Playbook) にして残りを複数の Devin セッションに並行で割り振る運用ができる。
- 実機での最終確認は人が行う。Devin が出すのは「シミュレータで検証済みの PR」。

## シーン 4: 結果を確認する (3 分)

```sh
git fetch && git checkout <Devin の PR ブランチ>
make lab-docker-start            # または make lab-ssh-start
perl bin/cbt-collect -i conf/devices.local-ssh.conf      # Devin が追加したインベントリ名に合わせる
diff <(grep -v '^!! CBT collected' output/TKY-ENB-0001/latest.cfg) \
     <(grep -v '^!! CBT collected' <Telnet で収集したファイル>)
make test
```

- 収集結果が Telnet 版と一致すること (ヘッダ行の日時以外)
- tcpdump で SSH のポート (2401) を見ても、もうパスワードは読めないこと
- PR の差分: 機種別コレクタの変更が最小であること、BG-7 の単体スクリプトも移行されていること

## バックアッププラン

- Devin の作業が時間内に終わらない / 方向がずれた場合: ブランチ `demo/ssh-reference` が移行後の参考実装 (Net::OpenSSH、パスワード / 公開鍵、Telnet との切り替え、SSH テスト付き)。`git diff main..demo/ssh-reference` で「Devin が出す PR はこういう形」と見せる。
- Docker が使えない環境: lab/ssh (公開鍵) だけでデモできる。パスワード認証は参考実装のテスト結果で説明する。
- `make test` は SSH ラボが起動していなければ SSH のテストをスキップする。

## 想定 Q&A

- **実機とシミュレータの差は?** シミュレータは CLI の振る舞い (プロンプト、ページャ、enable、認証失敗) を再現したもの。実機特有の挙動は、実機ログを Devin に渡せばシミュレータに追加できる。
- **ホスト鍵の検証は?** 参考実装は known_hosts ファイルを指定でき、本番は `StrictHostKeyChecking=yes` を想定。ラボでは初回接続時に登録 (`accept-new`)。
- **鍵やパスワードの管理は?** インベントリには環境変数参照 (`${CBT_PASSWORD}`) を書き、値は実行環境から渡す。
