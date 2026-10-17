#!/bin/sh
# 发布一次热更新
#
#   export HOTFIX_KEY=/path/to/hotfix-private.pem
#   ./tools/release.sh <载荷文件> <kind> [说明]
#
# 例子：
#   ./tools/release.sh ~/models-dev-api.json models "补充 12 个新模型"
#
# 做完三件事：算哈希 → 递增版本 → 签名。
# 然后 git add / commit / push 即可，无需其他操作。
set -e

REPO="$(cd "$(dirname "$0")/.." && pwd)"
MAN="$REPO/hotfix/manifest.json"
PAYLOAD="$1"
KIND="${2:-models}"
NOTES="${3:-}"

[ -n "$PAYLOAD" ] || { echo "用法: $0 <载荷文件> <kind> [说明]"; exit 1; }
[ -f "$PAYLOAD" ] || { echo "找不到载荷: $PAYLOAD"; exit 1; }
[ -n "$HOTFIX_KEY" ] || { echo "未设置 HOTFIX_KEY（私钥路径）"; exit 1; }
[ -f "$HOTFIX_KEY" ] || { echo "找不到私钥: $HOTFIX_KEY"; exit 1; }

case "$KIND" in
  models|prompt) ;;
  *) echo "不支持的 kind: $KIND（只允许 models / prompt）"; exit 1 ;;
esac

NAME="$(basename "$PAYLOAD")"
case "$NAME" in
  *[!A-Za-z0-9._-]*) echo "文件名含非法字符: $NAME"; exit 1 ;;
esac
# 长度也卡住，避免超长文件名在客户端被拒
[ ${#NAME} -le 80 ] || { echo "文件名过长"; exit 1; }

SHA=$(openssl dgst -sha256 -r "$PAYLOAD" | cut -d' ' -f1)
SIZE=$(wc -c < "$PAYLOAD" | tr -d ' ')
VER=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$MAN" | head -1)
VER=$(( ${VER:-0} + 1 ))

echo "→ $NAME  ${SIZE}B  sha256=${SHA:0:16}…  version→$VER"

mkdir -p "$REPO/hotfix/payload"
cp "$PAYLOAD" "$REPO/hotfix/payload/$NAME"

# 用 python3 拼 JSON，避免手写转义出错
python3 - "$MAN" "$VER" "$NAME" "$KIND" "$SHA" "$SIZE" "$NOTES" <<'PY'
import json, sys, datetime
mp, ver, name, kind, sha, size, notes = sys.argv[1:8]
m = json.load(open(mp, encoding='utf-8'))
m['version'] = int(ver)
m['issuedAt'] = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
if notes:
    m['notes'] = notes
# 同 kind 的旧条目替换掉，不同 kind 保留 —— 否则换 kind 就要重发全部
m['entries'] = [e for e in m.get('entries', []) if e.get('kind') != kind]
m['entries'].append({
    'name': name, 'kind': kind,
    'sha256': sha, 'size': int(size),
})
json.dump(m, open(mp, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
open(mp, 'a', encoding='utf-8').write('\n')
print(f"   清单已更新，共 {len(m['entries'])} 条")
PY

# 签名（签的是 manifest.json 的原始字节）
openssl dgst -sha256 -sign "$HOTFIX_KEY" -out /tmp/_hf.sig.der "$MAN"
base64 < /tmp/_hf.sig.der | tr -d '\n' > "$REPO/hotfix/manifest.sig"
rm -f /tmp/_hf.sig.der

echo "✓ 已签名"
echo
echo "接下来："
echo "  cd $REPO"
echo "  git add -A && git commit -m 'hotfix v$VER: $NOTES' && git push"
