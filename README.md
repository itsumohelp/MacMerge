# MacMerge

A visual diff tool for macOS.  
It offers a WinMerge-like workflow for comparing files and directories.

## Features

- **File compare** — Side-by-side line diff with encoding and line-ending indicators
- **Directory compare** — Tree view with changed/unchanged status and quick drill-down
- **Text input compare** — Paste text directly without creating files
- **Binary compare** — Detects whether binary files are identical
- **Auto reload** — Re-checks when focus returns to the window

## Installation

Download the latest `.dmg` from [Releases](../../releases).

## Finder Quick Action (right-click compare for two items)

You can compare two files/folders directly from Finder using a Quick Action.

1. Open **Automator** and create a new **Quick Action**
2. Set:
   - `Workflow receives current`: `files or folders`
   - `in`: `Finder`
3. Add **Run Shell Script**
4. Set input passing to: `as arguments`
5. Use this script:

```bash
if [ "$#" -ne 2 ]; then
  osascript -e 'display alert "Compare with MacMerge" message "Please select exactly two items" as warning'
  exit 1
fi

open -a "MacMerge" --args "$1" "$2"
```

6. Save it as, for example, `Compare with MacMerge`

Then: select two items in Finder → right click → **Quick Actions** → `Compare with MacMerge`.

## Requirements

- macOS 12 Monterey or later
- Intel and Apple Silicon supported

## License

MIT License — see [LICENSE](LICENSE).

This app uses open source software:

- [diff](https://github.com/kpdecker/jsdiff) — BSD-3-Clause

See [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES) for full license texts.

---

# MacMerge（日本語）

macOS 向けのビジュアル差分ツールです。  
WinMerge のような操作感で、ファイルやディレクトリの差分を確認できます。

## 機能

- **ファイル比較** — 行単位の差分をサイドバイサイド表示（文字コード・改行コード表示付き）
- **ディレクトリ比較** — ツリー表示で差異あり/なしを確認し、ファイル差分へ移動可能
- **テキスト入力比較** — ファイルを作らずテキスト貼り付けで比較
- **バイナリ比較** — バイナリファイルの一致/不一致を判定
- **自動再比較** — ウィンドウにフォーカス復帰時に再チェック

## インストール

[Releases](../../releases) から最新の `.dmg` をダウンロードしてください。

## Finder クイックアクション（右クリックで2項目比較）

macOS のクイックアクションを使うと、Finder で2つのファイル/フォルダを選んで `MacMerge` で比較できます。

1. **Automator** を起動し、新規 **クイックアクション** を作成
2. 上部設定を以下にする
   - `ワークフローが受け取る現在の項目`: `ファイルまたはフォルダ`
   - `場所`: `Finder`
3. アクション **シェルスクリプトを実行** を追加
4. 入力の引き渡し方法を `引数として` に設定
5. 次のスクリプトを設定

```bash
if [ "$#" -ne 2 ]; then
  osascript -e 'display alert "MacMergeで比較する" message "2つの項目を選択してください" as warning'
  exit 1
fi

open -a "MacMerge" --args "$1" "$2"
```

6. 例: `MacMergeで比較する` という名前で保存

以後、Finder で2項目選択 → 右クリック → **クイックアクション** → `MacMergeで比較する` で起動できます。

## 動作環境

- macOS 12 Monterey 以降
- Intel / Apple Silicon 対応

## ライセンス

MIT License — 詳細は [LICENSE](LICENSE) を参照してください。

使用 OSS:

- [diff](https://github.com/kpdecker/jsdiff) — BSD-3-Clause

各ライセンス全文は [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES) を参照してください。
