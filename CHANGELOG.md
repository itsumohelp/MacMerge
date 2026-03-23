# Changelog

## v2.0.3

### English

#### Improvements
- **Diff search UI removed** — Removed the in-view search input from the file diff screen to avoid header overlap and simplify the UI.
- **Window resize behavior improved** — Long file names in headers no longer force horizontal expansion, so manual resize/shrink works reliably.
- **Smaller initial window size** — Adjusted startup window and view base sizes to open at a smaller default size.

#### CI/CD
- **Draft-only build flow** — Updated release workflow trigger so build/release runs only when manually creating a draft release, avoiding duplicate builds at publish time.
- **Draft description from CHANGELOG** — Draft release body now pulls content from the matching `CHANGELOG.md` section instead of fixed text.

### 日本語

#### 改善
- **差分検索UIを削除** — ヘッダーとの重なりを避けるため、ファイル差分画面の検索入力欄を削除しました。
- **ウィンドウリサイズ挙動を改善** — 長いファイル名でもヘッダーが横方向に押し広げず、手動の拡大/縮小が効くようにしました。
- **初期ウィンドウサイズを縮小** — 起動時のデフォルトサイズと各ビュー初期サイズを小さめに調整しました。

#### CI/CD
- **Draft時のみビルドする運用へ変更** — リリースworkflowのトリガーを見直し、公開時の重複ビルドを避けるようにしました。
- **Draft本文をCHANGELOG連携** — 固定文ではなく、対象バージョンの `CHANGELOG.md` セクションを下書き本文に利用するようにしました。

## v2.0.2

### English

#### Improvements
- **Reload button in compare views** — Added `⟳ Reload` to both file diff view and directory compare view to refresh from current files.
- **Reload shortcut alignment** — `Cmd+R` now reloads in both file diff and directory compare views with the same behavior as the button.
- **Open file diff in new window from directory compare** — Selecting a changed file in directory compare now opens its diff in a separate window (no forced back-to-top navigation).

#### Testing
- **Launch smoke test** — Added one XCTest scenario to verify app launch creates an initial window controller.

### 日本語

#### 改善
- **比較画面に再読み込みボタン追加** — ファイル比較ビュー / ディレクトリ比較ビューの両方に `⟳ 再読み込み` を追加し、現在のファイル内容を再読込できるようにしました。
- **再読み込みショートカット統一** — 両ビューで `Cmd+R` による再読み込みをボタン押下と同一動作に統一しました。
- **ディレクトリ比較からの差分表示を別ウィンドウ化** — 変更ファイル選択時は別ウィンドウで差分を開くようにし、戻る操作でトップへ戻ってしまうストレスを解消しました。

#### テスト
- **起動スモークテスト追加** — アプリ起動時に初期ウィンドウコントローラが作成されることを確認する XCTest を1シナリオ追加しました。

## v2.0.1

### English

#### Improvements
- **Diff jump navigation** — Added previous/next diff navigation in the file diff header and shortcuts (`Cmd+↑` / `Cmd+↓`) to move across changed rows quickly.
- **Search bar layout fix** — Adjusted spacing so the search input no longer overlaps the diff view.

#### Docs
- **README bilingual structure** — Reorganized README to English first, then Japanese, and documented Finder Quick Action setup there.

### 日本語

#### 改善
- **差分ジャンプ操作を追加** — ファイル差分ヘッダーに「前/次の差分」操作を追加し、ショートカット（`Cmd+↑` / `Cmd+↓`）で差分行を素早く移動できるようにしました。
- **検索バー重なりを修正** — 検索入力欄が差分ビューに重ならないよう、レイアウトの間隔を調整しました。

#### ドキュメント
- **READMEの二言語構成を整理** — READMEを「英語 → 日本語」の順に再構成し、Finderクイックアクション手順もREADMEへ記載しました。

## v2.0.0

### アーキテクチャ
- **Swiftネイティブ版へ移行** — 主要な比較UIとロジックを Swift / AppKit ベースに移行

### 新機能
- **入力比較モード** — トップ画面に「入力して比較する」ボタンを追加。左右入力欄にテキストを入力し、上部の「比較する」で差分表示
- **比較中ドロップの新規ウィンドウ化** — 差分ビュー表示中に再度ファイル/フォルダをドロップすると、新しいウィンドウで比較を開始
- **ディレクトリ比較ツリー** — ディレクトリ階層を `▸/▾` で展開表示。ディレクトリ行に「差異あり / 差異なし」を表示

### 差分表示の改善
- **行番号表示の配置調整** — 左ガターと中央ガターの行番号表示を整理し、差分行との開始位置ずれを解消
- **情報バー追加** — 差分ビュー下部（詳細ビューの上）に、左右それぞれの文字コード・改行コードを表示

### 入力体験の改善
- **入力欄の操作性向上** — ダークモードでの視認性を改善し、左右入力欄でのフォーカス移動・ペースト・選択ショートカット（`Ctrl/Cmd + A/C/V/X/Z/Y`）を安定化
- **長文の折り返し抑止** — 入力欄は横スクロール優先で表示

## v1.2.0

### 新機能
- **AIプロンプト連携** — 右上の ✏️ ボタンでプロンプト入力パネルを開閉。入力内容は localStorage に自動保存
- **クリップボードコピー** — 右上の 📋 ボタンで「プロンプト + before/after の比較内容」をまとめてクリップボードにコピー。ファイル比較・テキスト入力比較・ディレクトリ内ファイル比較のいずれでも動作

### UI改善
- **右上コントロールの統合** — テーマ切り替え・プロンプトボタン・テキスト比較ボタンを1つのコンテナに集約し、重なりを解消。表示頻度順（左から：比較ボタン → プロンプト系 → テーマ切り替え）に配置
- **差分行の行番号透過を修正** — `position: sticky` な行番号セルが横スクロール時に背後を透かす問題を修正。削除行・追加行とも不透明な背景色を適用（ダーク・ライト両モード対応）

## v1.1.9

### ビルド
- **ユニバーサルバイナリ対応** — Apple Silicon (arm64) と Intel (x86_64) の両アーキテクチャに対応した Universal Binary でビルドするよう GitHub Actions を変更

## v1.1.8

### 差分表示の改善
- 横スクロール時の行番号背景が透過しないように修正（行番号の視認性を改善）
- 行内差分のアラインロジックを改善し、追記・削除時のみ空白補完して後続比較のずれを抑制
- 内容差が大きい行は行全体差分として扱うよう判定を調整
- 構造化行の差分可視化を強化し、共通ラベル/キーは非差分、値部分のみ差分表示
  - JSON形式（`"key": value`）
  - 引用値形式（例: `echo "..."`）
  - 代入形式（`key=value`, `export KEY=value`, `--flag=value`）
  - コロン区切り形式（`Header: value`）

## v1.1.7

### 新機能
- **テーマ切り替えスイッチ** — 画面右上にダーク/ライトモード切り替えスイッチを追加
- **ライトモード対応** — 既存UIの各画面（ドロップ画面、比較画面、テキスト入力画面、差分パネル）にライトモード配色を追加

### 仕様
- **デフォルトテーマ** — 起動時の既定をダークモードに設定（切り替え状態は保存時のみ復元）

## v1.1.6

### 新機能
- **マルチウィンドウ対応** — 差分表示中・テキスト入力中にファイルやフォルダをドロップすると新しいウィンドウで比較を開く。1ファイルのドロップでパスが入力済みの状態で開き、2ファイルのドロップで即座に差分比較を実行
- **行末改行コードアイコン** — 差分表示の各行末に改行コードを示すアイコンを表示（`↵` LF / `⏎` CRLF / `↩` CR）。混在ファイルでは行ごとに正確なアイコンを表示
- **行比較パネルに文字コード・改行コード表示** — ダブルクリックで開く差分詳細パネルのヘッダーに、現在比較中のファイルの文字コードと改行コードを表示

## v1.1.5

### アーキテクチャ
- Electron 32 から Tauri v2 + Rust に全面書き替え
- 不要になった Electron 関連ファイル（main.js, preload.js, macmerge.html, dist/, assets/）を削除

### 新機能
- **テキスト入力比較モード** — ドロップ画面に「入力する」ボタンを追加。ファイルなしで直接テキストを貼り付けて差分比較できる（F5 で実行）
- **文字コード・改行コード表示** — ファイル比較時に画面下部へ文字コード（UTF-8 / UTF-8 BOM）と改行コード（LF / CRLF / CR / Mixed）を表示
- **文字コードダイアログ** — 文字コードが異なる場合（UTF-8 vs UTF-8 BOM）、BOM を除外して比較するか確認するダイアログを表示
- **ディレクトリ比較: ツリー表示** — フラットなリストからディレクトリ構造を可視化したツリー表示に変更。ディレクトリは折りたたみ可能で、初期表示はすべて閉じた状態
- **ディレクトリ比較: 文字コード・改行コード表示** — ファイルを選択した際に文字コードと改行コードをパネル下部に表示
- **バイナリファイル比較** — バイナリファイルを検出し、一致 / 不一致を表示

### 差分表示の改善
- 行揃えのためのフィラー行（空行）のハイライトを除去し、追加・削除行との区別を明確化

### リリース自動化
- GitHub Actions による署名・公証済み DMG の自動ビルドを設定
- タグ（`v*`）をプッシュすると自動的にビルド・署名・公証・Draft リリース作成まで実行
- バージョン番号を `package.json` / `tauri.conf.json` / `Cargo.toml` でタグに自動同期
- リリースノートは `CHANGELOG.md` から自動抽出

### その他
- `.gitignore` に Tauri / Rust ビルド成果物を追加
- `README.md` を Tauri 版に合わせて書き直し
