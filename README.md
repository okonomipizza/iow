# IOW

学習中の言語をその言語で学びたい方向けの翻訳アプリ。

## 必要環境

- macOS
- Xcode 26 以降（Swift 6.3 以降）

## インストール

ビルド済みのアプリは配布していないため、お使いの Mac でビルドをお願いします。

### 1. コード署名の準備（初回のみ）

```sh
./IOW/Scripts/setup-dev-signing.sh
```

自己署名の Code Signing 証明書を login キーチェーンに作成します（実行時にパスワードを求められます）。macOS の Accessibility / Input Monitoring の許可は「bundle ID + 署名」の組で記録されるため、ad-hoc 署名のままだと再ビルドのたびに ⌘G が黙って効かなくなります。署名を安定させるのがこの手順の目的です。

### 2. ビルドして配置

```sh
cd IOW
xcodebuild -project IOW.xcodeproj -scheme IOW \
  -destination 'platform=macOS' build
```

できあがった `IOW.app` を `~/Applications` へ置きます。

```sh
APP="$(xcodebuild -project IOW.xcodeproj -scheme IOW \
  -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2}')/IOW.app"
mkdir -p ~/Applications
rm -rf ~/Applications/IOW.app
cp -R "$APP" ~/Applications/
open ~/Applications/IOW.app
```

初回起動時に Accessibility と Input Monitoring の許可を求められます。許可後は一度終了して起動し直してください（`CGEventTap` は起動時に作られるため）。

## 使い方

1. アプリを起動する（メニューバーに常駐する）
2. メニューバーのアイコン →「設定…」から Gemini API キーを保存する（[https://aistudio.google.com/apikey](https://aistudio.google.com/apikey) で発行）
3. 設定から翻訳先の言語を選ぶ（既定は日本語。翻訳元は自動で判断される）
4. 翻訳したいテキストを選択して、設定したショートカットを押す（既定は ⌘G）

翻訳結果はカーソル付近のポップアップに表示されます。外側をクリックで閉じ、背景をドラッグで移動でき、右下のボタンで本文をクリップボードへコピーできます。メニューバーから Translate / Simplify を切り替えられます。

## ライセンス

MIT
