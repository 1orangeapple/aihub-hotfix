# AIHub 热更新通道

数据热更新用的仓库。**不含可执行代码**，只有数据和签名。

## 这个仓库解决什么问题

之前的热更新只校验 SHA-256 —— 但哈希和文件来自同一个地方，
谁能改文件谁就能改哈希，校验等于没做。

现在改成 **ECDSA P-256 签名**：

```
发布端                          客户端（APK 内置公钥）
  │                                    │
  ├─ manifest.json ──── 私钥签名 ──→  验签 ✗ = 直接拒绝
  ├─ manifest.sig                      │
  └─ payload/*.json ─── SHA-256 ──→   验哈希 ✗ = 拒绝
```

攻击者就算拿下仓库、劫持域名，**没有私钥就签不出能被接受的清单**。
这是「纯哈希校验」和「签名校验」的本质区别。

---

## 首次配置（只做一次）

### 1. 生成密钥

```sh
cd tools && chmod +x hotfix.sh
./hotfix.sh keygen
```

会打印一对密钥，然后**立刻删掉本地的私钥文件**：

```sh
rm hotfix-private.pem
```

### 2. 公钥写进 App

把打印出来的公钥贴到：

```
app/src/main/java/com/minis/aihub/update/SignedUpdate.kt
  → PUBLIC_KEY_B64 = "刚才那串"
```

同时把 `CHANNEL` 改成你的仓库地址：

```kotlin
const val CHANNEL = "https://raw.githubusercontent.com/你的用户名/仓库名/main/hotfix"
```

**改公钥必须重新发 APK。** 这是设计使然 —— 否则换密钥就不需要用户同意，
那签名机制就白做了。

### 3. 私钥存进 GitHub Secrets

仓库 → Settings → Secrets and variables → Actions → New repository secret

- Name: `HOTFIX_PRIVATE_KEY`
- Value: `keygen` 打印的那段（含 `-----BEGIN EC PRIVATE KEY-----` 到 `-----END EC PRIVATE KEY-----`）

### 4. 推上去

```sh
git remote add origin git@github.com:你的用户名/仓库名.git
git add -A && git commit -m "init" && git push -u origin main
```

---

## 日常发布

```sh
export HOTFIX_KEY=~/hotfix-private.pem     # 私钥（本地留一份或用 CI）
./tools/release.sh ~/models-dev-api.json models "补充 12 个模型"
git add -A && git commit -m "hotfix v2" && git push
```

脚本会自动：算哈希 → 递增版本号 → 更新清单 → 签名。

推送后 CI 会**再签一次**作为双保险（防止本地忘了签）。

### version 必须递增

客户端靠它防回滚：只接受 `version > 已应用版本` 的清单。
写回旧版本号不会生效，这是有意为之 —— 阻止"把用户降级到有漏洞的旧数据"。

### kind 白名单

| kind | 对应 | 客户端行为 |
|---|---|---|
| `models` | 模型能力库 JSON | 替换 `data/models-dev-api.json` |
| `prompt` | 系统提示词 | 替换 `hotfix/system_prompt.txt` |

**新增 kind 必须同时改客户端代码。** 客户端遇到不认识的 kind 会跳过，
不会尝试执行 —— 这是刻意的安全边界。

---

## 这套机制挡不住什么

必须说清楚：

1. **私钥泄漏 = 全盘失守。** 拿到私钥的人能给所有用户推任意数据。
   所以私钥只在 CI Secret 和你的离线备份里，不要放进仓库、不要贴进聊天窗口。
2. **只保护"数据"，不保护"代码"。** 逻辑改动必须重新发 APK 并让用户安装。
   这不是妥协 —— 让远端推代码执行，等于给每台手机开后门。
3. **APK 本身被改的话，内置公钥也能被换。** 所以 APK 要有自己的签名
   （Android 的 app signing），且分发渠道要可信。
4. **重放攻击已被防住**（version 单调递增），但**降级到旧密钥**防不住 ——
   换密钥只能通过发新版 APK。
