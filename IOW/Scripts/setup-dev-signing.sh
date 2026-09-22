#!/usr/bin/env bash
# 開発ビルド用の自己署名コード署名証明書を作る。
#
# なぜ必要か
# ad-hoc 署名のビルドはビルドのたびに cdhash が変わる。TCC は許可を
# 「bundle ID + designated requirement」の組で記録するが、ad-hoc 署名の
# requirement はその cdhash に紐づくため、再ビルドのたびに
# Accessibility / Input Monitoring の許可が無効になり、ホットキーが黙って
# 効かなくなる。安定した証明書で署名すれば requirement が証明書ベースになり、
# 許可が再ビルド後も維持される。
#
# スコープ
# 証明書はこの Mac の login キーチェーンにだけ作られ、秘密鍵をリポジトリへ
# 含めることはない。したがって開発マシンごとに 1 回実行すればよい。IOW は
# 署名済みバイナリとして配布しないため、Developer ID も notarization も
# 使わない（Gatekeeper が Developer ID を要求するのはダウンロードしてきた
# 実行ファイルに対してで、自分でビルドしたものには quarantine 属性が付かない）。
# 証明書名は `Config/Shared.xcconfig` の `IOW_CODE_SIGN_IDENTITY` に結び付いて
# いる。名前を変えたらこのスクリプトを再実行すること。
#
# このスクリプトが行うこと（手順）
#   1. 同じ名前のコード署名 identity が既にあれば何もしない（作り直すと
#      designated requirement が変わり、TCC の許可が落ちる）。
#   2. 自己署名の RSA 鍵ペアと、コード署名用の拡張を持つ証明書を生成する。
#      LibreSSL（/usr/bin/openssl）は `-addext` を安定して扱えないため、
#      拡張は設定ファイル経由で渡す。
#   3. 鍵と証明書を PKCS#12 バンドルにまとめる。PKCS#12 はここでは運搬用の
#      形式にすぎず、バンドルは一時ディレクトリに書き、終了時に消す。
#      macOS は空パスワードで保護されたバンドルを import しないため、
#      使い捨てのパスワードを使う。
#   4. バンドルを login キーチェーンへ import し、秘密鍵を /usr/bin/codesign
#      と /usr/bin/security に使わせる。
#   5. 証明書をコード署名用として信頼済みに設定する。コード署名の信頼設定が
#      無いと identity が有効と見なされず、codesign が使おうとしない。
#   6. 初回の後始末を案内する: bundle ID の TCC 許可をリセットし、アプリを
#      起動して許可を取り直す。
set -euo pipefail

# コード署名 identity の名前。別の名前を試すときにファイルを編集せず済むよう
# 環境変数で差し替えられる。
CERT_NAME="${IOW_SIGNING_IDENTITY:-IOW Development}"

# このアプリの bundle identifier は固定（`Config/Shared.xcconfig`）。ここに
# もう一度書くのは、末尾で案内する tccutil 用のメッセージのためだけである。
BUNDLE_IDS=("com.okonomipizza.IOW")
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
# 自己署名証明書の有効期間。10 年。TCC の許可は証明書に紐づくため、短いと
# 再びホットキーが黙って効かなくなる。
VALID_DAYS=3650

# 常にシステムの LibreSSL を使う。PATH の先頭に Homebrew / nix の OpenSSL 3 が
# あると、macOS の Security フレームワークが import を拒否する方式の
# PKCS#12 を出力してしまう。
OPENSSL=/usr/bin/openssl

# PKCS#12 の運搬用バンドルのパスワード（手順 3 を参照）。
P12_PASSWORD=iow-dev-transport

if [[ ! -f "$KEYCHAIN" ]]; then
  echo "error: login keychain not found: $KEYCHAIN" >&2
  exit 1
fi

# 手順 1: 同じ名前の identity が既にあれば終了する。これにより、このスクリプトは
# 何度実行しても安全（冪等）になる。
if security find-identity -v -p codesigning | grep -qF "$CERT_NAME"; then
  echo "Code signing identity already present: $CERT_NAME"
  security find-identity -v -p codesigning | grep -F "$CERT_NAME"
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# 手順 2: 鍵ペアと証明書を生成する。`prompt = no` で対話を省略し、
# コード署名用の拡張（v3_codesign）が証明書をコード署名 identity として
# 使えるものにする。
cat > "$TMP_DIR/openssl.cnf" <<EOF
[ req ]
distinguished_name = dn
prompt = no
x509_extensions = v3_codesign

[ dn ]
CN = ${CERT_NAME}

[ v3_codesign ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

echo "Generating self-signed code signing certificate: $CERT_NAME"
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -sha256 \
  -days "$VALID_DAYS" \
  -config "$TMP_DIR/openssl.cnf" \
  -keyout "$TMP_DIR/key.pem" \
  -out "$TMP_DIR/cert.pem" 2>/dev/null

# 手順 3: 鍵と証明書を PKCS#12 バンドルへまとめ、import の段に渡す。
"$OPENSSL" pkcs12 -export \
  -inkey "$TMP_DIR/key.pem" \
  -in "$TMP_DIR/cert.pem" \
  -out "$TMP_DIR/identity.p12" \
  -name "$CERT_NAME" \
  -passout "pass:$P12_PASSWORD"

# 手順 4: login キーチェーンへ import する。`-T` で指定した 2 つのツールが
# この秘密鍵を使えるようになります。macOS は初回署名時にキーチェーンの
# パスワードを尋ねることがある。そのときは「常に許可」を選ぶこと。
echo "Importing into the login keychain (a password prompt may appear)"
security import "$TMP_DIR/identity.p12" \
  -k "$KEYCHAIN" \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security

# 手順 5: 証明書をコード署名用として信頼済みに設定する。この段は login の
# パスワードを尋ねることがある。
echo "Marking the certificate as trusted for code signing"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP_DIR/cert.pem"

# 手順 6: 結果と、初回ビルド後の一度きりの後始末を案内する。
echo
echo "Done. Available code signing identities:"
security find-identity -v -p codesigning

echo
echo "Next steps (one time, after the first build with the new identity):"
echo
for bundle_id in "${BUNDLE_IDS[@]}"; do
  echo "  tccutil reset Accessibility ${bundle_id}"
  echo "  tccutil reset ListenEvent ${bundle_id}"
done
cat <<'EOF'

Then launch the app and grant the permissions again. Later rebuilds keep them.

Reset only the bundle identifiers you have actually granted before. A machine
that previously ran a Developer ID signed build of com.okonomipizza.IOW needs
that one too: the grant is recorded against the old signature and no longer
matches.
EOF