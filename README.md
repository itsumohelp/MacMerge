# MacMerge

macOS 向けのビジュアル差分ツールです。WinMerge のような操作感で、ファイルやディレクトリの差分を確認できます。

## 使い方

2つのファイル（またはフォルダ）をウィンドウにドロップするだけで、差分がハイライト表示されます。

- **ファイル比較** — 行単位の差分をサイドバイサイドで表示
- **ディレクトリ比較** — フォルダ内のファイル一覧を比較し、変更されたファイルをクリックすると差分を確認できる

## インストール

[Releases](../../releases) から最新の `.dmg` をダウンロードしてインストールしてください。

現在 Apple Developer Program の審査中のため、このバージョンは未署名です。初回起動時に Gatekeeper にブロックされた場合は以下の手順で開けます。

1. アプリを開こうとしてブロックされる
2. **システム設定 → プライバシーとセキュリティ** を開く
3. 画面下部に表示される **「このまま開く」** をクリック
4. 確認ダイアログで **「開く」** をクリック

署名済みバージョンが準備でき次第、この手順は不要になります。

## 動作環境

- macOS 12 Monterey 以降
- Intel / Apple Silicon 両対応（Universal Binary）

## ライセンス

MIT License — 詳細は [LICENSE](LICENSE) を参照してください。

本アプリは以下のオープンソースソフトウェアを使用しています。

- [diff](https://github.com/kpdecker/jsdiff) — BSD-3-Clause
- [diff2html](https://github.com/rtfpessoa/diff2html) — MIT
- [Electron](https://github.com/electron/electron) — MIT

各ライセンス全文は [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES) を参照してください。
