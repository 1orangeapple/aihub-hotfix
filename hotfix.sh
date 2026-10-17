#!/bin/sh
# 热更新签名工具
#
#   ./hotfix.sh keygen            生成密钥对（只做一次）
#   ./hotfix.sh sign <目录>        给目录里的 manifest.json 签名
#   ./hotfix.sh verify <目录>      本地验证签名是否正确
#
# 依赖：openssl
set -e

SIG_ALG="-sha256"

case "${1:-}" in
  keygen)
    echo "→ 生成 ECDSA P-256 密钥对…"
    openssl ecparam -name prime256v1 -genkey -noout -out hotfix-private.pem
    chmod 600 hotfix-private.pem

    # Java 要的是 X.509 SubjectPublicKeyInfo（DER），转成 base64 一行
    openssl ec -in hotfix-private.pem -pubout -outform DER 2>/dev/null \
      | base64 | tr -d '\n' > hotfix-public.b64

    echo
    echo "=========== 公钥（贴进 SignedUpdate.kt 的 PUBLIC_KEY_B64）==========="
    cat hotfix-public.b64; echo
    echo "===================================================================="
    echo
    echo "=========== 私钥（放进 GitHub Secrets：HOTFIX_PRIVATE_KEY）==========="
    cat hotfix-private.pem
    echo "====================================================================="
    echo
    echo "⚠️  私钥生成后立刻删掉本地副本：rm hotfix-private.pem"
    echo "⚠️  私钥一旦泄漏，任何人都能给你的所有用户推更新。"
    ;;

  sign)
    DIR="${2:-.}"
    [ -f "$DIR/manifest.json" ] || { echo "找不到 $DIR/manifest.json"; exit 1; }

    openssl dgst $SIG_ALG -sign "${HOTFIX_KEY:-hotfix-private.pem}" \
      -out "$DIR/manifest.sig.der" "$DIR/manifest.json"
    base64 < "$DIR/manifest.sig.der" | tr -d '\n' > "$DIR/manifest.sig"
    rm -f "$DIR/manifest.sig.der"

    echo "✓ 已签名：$DIR/manifest.sig"
    echo "  清单 SHA-256: $(openssl dgst -sha256 -r "$DIR/manifest.json" | cut -d' ' -f1)"
    ;;

  verify)
    DIR="${2:-.}"
    base64 -d < "$DIR/manifest.sig" > /tmp/_sig.der 2>/dev/null || cp "$DIR/manifest.sig" /tmp/_sig.der
    if openssl dgst $SIG_ALG -verify "${HOTFIX_PUB:-hotfix-public.pem}" \
         -signature /tmp/_sig.der "$DIR/manifest.json"; then
      echo "✓ 签名有效"
    else
      echo "✗ 签名无效"
      exit 1
    fi
    ;;

  *)
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    ;;
esac
