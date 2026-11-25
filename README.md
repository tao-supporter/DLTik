# DLTik

TikTok / Douyin のリンクを貼るだけで、動画と画像投稿をダウンロードできる iOS アプリ。

- 取得の仕組みは R⤓Download（ショートカット）の TikTok 分岐と同じ流れ
  1. 設定ファイル（moody0100.com/file/242）から送信先ドメイン一覧を取得
  2. そのうち 1 つへ `/api/ajaxSearch` に POST
  3. 応答 HTML から Download リンクを抽出
  - 取れなかった場合は tikwm の API にフォールバック（画像投稿の画像一覧はこちらで補完）
- ダウンロードは進捗バー・パーセント・容量表示つき、複数同時OK
- 保存した動画はアプリ内でプレビュー再生、画像は拡大表示、そのまま写真アプリへ保存や共有ができる
- ダウンロード履歴は持たない

ビルドは GitHub Actions の「Build unsigned IPA」を手動実行すると、未署名 IPA が Artifacts に出る。
プロジェクトは XcodeGen（project.yml）から生成する。

アプリアイコンは `DLTik/Assets.xcassets/AppIcon.appiconset/icon-1024.png`（1024×1024）を置く。
