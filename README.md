# vROps Super Metrics — Snapshot VM 統計

兩個拿來抓「忘了刪的 VM 快照」的 super metric,給 VMware Aria Operations (vROps) 用。
**同一組 formula** 可以同時在多個物件層級看到對應範圍的總數:

| Enable 在哪個 Object Type | 看到的是 |
| --- | --- |
| **Cluster Compute Resource** | 那個 Cluster 底下有快照的 VM 數 |
| **VMwareAdapter Instance**(每個 vCenter) | 那個 vCenter 底下所有 VM 的快照數 |
| **Datacenter** | 那個 Datacenter 底下的快照數 |
| **vSphere World** | 整個 vROps 看得到的所有 VM(全 lab 加總) |

因為 formula 用 `depth=10`,super metric 會自動往下找 VM 子物件,所以不用為每個層級各寫一份。Policy 裡多 enable 幾個 Object Type 就會多看到幾條線。

| 項目 | 值 |
| --- | --- |
| 目標 vROps 版本 | Aria Operations 8.18.x(8.x 普遍可用) |
| Attach 物件類型 | `ClusterComputeResource` + `VMwareAdapter Instance`(by vCenter),其它層級隨需求加 |
| 依賴 metric | VM property `diskspace\|snapshot\|snapshotAge` |
| Lab 範例 vROps | `https://10.0.0.111` (`admin` / `VMware1!`) |

---

## TL;DR

```bash
# 1. 透過 API 建立兩個 super metric(只需要 admin 帳號)
git clone https://github.com/kostenyang/vropssupermetric.git
cd vropssupermetric
VROPS_HOST=10.0.0.111 VROPS_USER=admin VROPS_PASS='VMware1!' \
    bash apply.sh
```

```text
# 2. 進 vROps UI → Configure → Policies → 編輯 Active Default Policy
#    → Collect Metrics and Properties → Object Type: Cluster Compute Resource
#    → 過濾 Super Metric → 把這兩個從 inherited 改成 Enabled → Save
```

跑完 vROps 一個收集週期(預設 5 分鐘),Cluster 物件 → All Metrics → Super Metrics 就會看到值。

---

## 為什麼用 `diskspace|snapshot|snapshotAge`

vROps 對每台 VM 都會收一個 property 叫 `diskspace|snapshot|snapshotAge`,語意是:

| 值 | 意思 |
| --- | --- |
| `-1` | 這台 VM **沒有** snapshot |
| `0` | 有 snapshot,且建立 < 1 天 |
| `N (>0)` | 有 snapshot,最舊的那顆已存在 N 天 |

所以判斷 `>= 0` 就是「有 snapshot」;判斷 `> 90` 就是「超過 90 天」。
用 property 比用 `diskspace|snapshot|used > 0` 穩,因為剛建立、還沒寫入的 snapshot disk usage 也可能是 0。

---

## Formula

### 1. Snapshot VM Count(有快照的 VM 總數)

```text
count(${depth=10, adapterkind=VMWARE, resourcekind=VirtualMachine, attribute=diskspace|snapshot|snapshotAge, where=">= 0"})
```

### 2. Snapshot VM Count (Over 90 Days)(快照 > 90 天的 VM 總數)

```text
count(${depth=10, adapterkind=VMWARE, resourcekind=VirtualMachine, attribute=diskspace|snapshot|snapshotAge, where="> 90"})
```

### Formula 各 token 說明

| Token | 用途 |
| --- | --- |
| `count(...)` | 聚合函數,計算回傳資料點數 |
| `depth=10` | 從 attach 物件往下找 10 層子物件,Cluster → Host → VM 用 10 綽綽有餘 |
| `adapterkind=VMWARE` | 限制只看 VMware Adapter 的物件 |
| `resourcekind=VirtualMachine` | 只看 VM(不要把 Template / vApp 之類包進來) |
| `attribute=diskspace\|snapshot\|snapshotAge` | 用 snapshotAge 這個 property/metric 當判斷依據 |
| `where=">= 0"` / `where="> 90"` | 過濾條件,語法是 `"<運算子> <數字>"`,**留意 super metric API 用 `where` 而不是 `whereClause`** |

---

## 安裝方式 A:用 `apply.sh`(透過 REST API)

`apply.sh` 會用 vROps `/suite-api/api/supermetrics` 端點 POST 兩份 JSON。
**只建立 super metric 物件本身**,不會自動 enable 在 policy 上(policy enable 在 UI 做,見下節)。

```bash
# Linux / macOS / Git Bash
VROPS_HOST=10.0.0.111 VROPS_USER=admin VROPS_PASS='VMware1!' bash apply.sh
```

PowerShell:

```powershell
$env:VROPS_HOST='10.0.0.111'
$env:VROPS_USER='admin'
$env:VROPS_PASS='VMware1!'
bash apply.sh   # 或下 `pwsh apply.ps1`(如果你之後加)
```

成功後輸出兩筆 `HTTP 201`,可在 vROps UI → **Configure → Super Metrics** 看到。

### 已經有同名 super metric 怎麼辦

API 會擋住同名 super metric 重複建立(回 409 / 500)。
要重跑就先刪舊的:

```bash
# 找 ID
curl -sk -u admin:VMware1! "https://10.0.0.111/suite-api/api/supermetrics" \
    -H 'Accept: application/json' | jq -r '.superMetrics[] | "\(.id)  \(.name)"'

# 刪
curl -sk -u admin:VMware1! -X DELETE \
    "https://10.0.0.111/suite-api/api/supermetrics/<ID>"
```

---

## 安裝方式 B:手刻(只貼 formula)

不想跑 script、直接複製 formula 到 UI 也行:

1. vROps UI → **Configure → Super Metrics → Add**
2. **Name** 填 `Snapshot VM Count`(或 `Snapshot VM Count (Over 90 Days)`)
   - ⚠️ 名稱**不可以**含 `<` 或 `>`,所以括號裡寫 `Over 90 Days`,別用 `>90`
3. **Formula** 直接貼上面那段 `count(${...})`
4. Save

---

## 啟用在 Policy(必做,不然不會收)

vROps 8.x 公開 REST API **沒有**端點可以在 policy 裡啟用 super metric(只有 pricing settings 開放,別的 policy 設定都在 internal API 走 ZIP import/export)。
所以這一步只能在 UI 點:

1. **Configure → Policies**
2. 找 active 的 default policy(Lab 是 `vSphere Solution's Default Policy`,旁邊有 ★),點 **Edit**
3. 左側分頁切到 **「Collect Metrics and Properties」**
4. 上方 Object Type 下拉先選 **「Cluster Compute Resource」**
5. 右上 filter 切到 **「Super Metric」**
6. 找到 `Snapshot VM Count` 和 `Snapshot VM Count (Over 90 Days)`,**State** 從 `inherited` 改成 **Enabled / Activated**
7. **重複 step 4–6,把 Object Type 改成 「VMwareAdapter Instance」**(這層就是 by vCenter)
   - 一樣 enable 同兩個 SM
   - 之後同一個 SM,在 Cluster object 看到的是 cluster 範圍的總數,在 vCenter adapter instance 看到的是整個 vCenter 的總數
8. 右下 **Save**

### 同理:要看 by Datacenter / by 整個 lab

把 step 4 換成 `Datacenter` 或 `vSphere World`,enable 同樣兩個 SM 即可。
Formula 共用、不用建新的,因為 `depth=10` 會自動往下抓所有 VM 子物件。

---

## 驗證

啟用 + 等一個收集週期(預設 5 分鐘):

```bash
# 找 Cluster resource id
curl -sk -u admin:VMware1! \
    "https://10.0.0.111/suite-api/api/resources?resourceKind=ClusterComputeResource" \
    -H 'Accept: application/json' | jq -r '.resourceList[] | "\(.identifier)  \(.resourceKey.name)"'

# 或找 vCenter Adapter Instance(by vCenter 的那層)
curl -sk -u admin:VMware1! \
    "https://10.0.0.111/suite-api/api/resources?resourceKind=VMwareAdapter%20Instance" \
    -H 'Accept: application/json' | jq -r '.resourceList[] | "\(.identifier)  \(.resourceKey.name)"'

# 看 latest stats(super metric 也會在這裡)
curl -sk -u admin:VMware1! \
    "https://10.0.0.111/suite-api/api/resources/<RESOURCE_ID>/stats/latest" \
    -H 'Accept: application/json' | jq '.values[].["stat-list"].stat[] | select(.statKey.key | contains("Snapshot VM"))'
```

或 UI:Cluster / vCenter object → **All Metrics → Super Metrics** 樹下會出現兩條線。

---

## 常見踩雷

| 症狀 | 原因 | 處理 |
| --- | --- | --- |
| 建立時回 `Super Metric name cannot contain less-than or greater-than symbols` | SM 名稱用了 `>` 或 `<` | 改成 `(Over N Days)` 之類 |
| Formula 收到 `'whereclause' cannot be resolved` | token 拼字 | 用 `where=`,不是 `whereclause=` / `whereClause=` |
| SM 已建立但 Cluster 看不到值 | policy 沒 enable | 走上面「啟用在 Policy」那一節 |
| 數字一直是 0,但 vCenter 看得到有快照的 VM | depth 不夠或 attach 在錯的 object type | depth 拉到 10、attach 在 Cluster / Datacenter / vCenter Adapter Instance |
| 重建同名 SM 失敗 | 同名已存在 | 先 DELETE 舊的(見上面範例) |

---

## 相關連結

- vROps Super Metric 官方文件:<https://techdocs.broadcom.com/us/en/vmware-cis/aria/aria-operations.html>
- 本 lab 整體環境筆記:鄰近 repo `kostenyang/openwebui`
