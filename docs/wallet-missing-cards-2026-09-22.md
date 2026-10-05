# Wallet 漏识别记录：国泰会员卡与中国银行

- 日期：2026-09-22（Asia/Hong_Kong）
- 状态：未解决；已完成一次配合真机操作的日志采集。
- 测试版本：`kyler/dev`，`3f9ef23`（`fix: require live iPhone card verification`）。
- 设备：iPhone 15 Pro，`iPhone16,1`，iOS 18.6.2；通过 USB 连接 Mac。
- 范围：只读日志与本地缓存分析，没有修改手机卡片，也没有刷写皮肤。

## 现象与预期

用户反馈：大部分卡能在首次扫描中出现，其余部分卡可通过双击侧键、认证并选卡后出现；国泰会员卡和中国银行银联卡仍未进入列表。截图显示 Screen 有 12 张卡。

预期：能可靠确认属于当前 iPhone 的卡应显示在对应槽位；不能用 Mac 缓存中的候选记录直接替代手机存在性验证。界面数量只表示本次识别结果，不是 Wallet 总卡数。

## 复现步骤

1. 在上述版本启动扫描，并连接 iPhone 的统一日志服务 `com.apple.os_trace_relay`。
2. 双击 iPhone 侧键，通过 Face ID，选中中国银行卡，在 `Hold Near Reader` 界面停留约 5 秒。
3. 用户确认“中国银行好了”后，再打开国泰会员卡，显示完整二维码约 5 秒。
4. 点击国泰卡右下角信息按钮，查看详情后返回卡面；用户确认“国泰好了”。
5. 分别检查两次操作期间的日志，比较激活标识、卡片路径与本地缓存映射。

诊断采集已结束。下列证据已脱敏；原始设备日志、完整卡片 ID、会员号、二维码和设备标识不纳入仓库。

## 国泰会员卡：手机输出了 ID，当前解析器未覆盖

### 已观察到的证据

- Mac 本地存在 `Cathay Pacific · Membership card` 记录，ID 长度为 28，符合当前路径解析器对 ID 字符的要求。
- 本地卡券资料包含条码配置，没有 `nfc` 字段。这是本地缓存的属性，不能单独证明手机当前状态。
- 22:57:27 的手机 `nfcd` 日志出现完整 ID，与上述国泰记录精确一致。相关结构如下：

```text
nfcd: NFExpressModeManager ... globalSet={(
    "<CATHAY_PASS_ID>"
)}
nfcd: Express mode limited to type: (0 -> 0),
      passIDs[InSession]: (null), passIDs[global]: {(
    "<CATHAY_PASS_ID>"
)}
```

- 国泰操作时段也有资源查询，但未捕获到可供现有规则使用的国泰 `.pkpass` 文件路径。部分字段显示为 `<private>`；不能推断这些隐藏字段必然包含所需 ID。

### 当前代码限制

`Sources/WalletDiscovery.swift` 只解析特定 `.pkpass`、`.cache`、`.pkcache` 路径和 `setActivePaymentApplet ... requestedApplet ... identifier=`。它没有解析上述多行 `passIDs[global]` 结构。

`ScreenApp.swift` 逐行过滤 Wallet 上下文；独立的 `nfcd` 消息及仅包含 ID 的续行也可能被过滤。因此，修复需要检查完整消息的上下文保留，不能只放宽 ID 正则表达式。

### 结论与待确认事项

已找到手机确实提供、但当前扫描器没有利用的 ID 信号。不过，`passIDs[global]` 属于 Express Mode 配置上下文，不能仅凭出现时间就认定它表示“当前选中卡”，也尚未证明它保证卡此刻仍在 Wallet。

- [ ] 通过切换其他卡与重复打开国泰的对照测试，确认该字段的含义和时效性。
- [ ] 如证据足够，增加带消息上下文的解析，并使用合成、多行日志编写回归测试。
- [ ] 验证无关配置事件、旧记录或裸 ID 不会被误当作已确认卡片。

## 中国银行：有激活标识，缺少卡片文件 ID 映射

### 已观察到的证据

- 用户已正确进入 `Hold Near Reader` 界面。
- 22:56:57 捕获到 `setActivePaymentApplet` 的 `requestedApplet` 标识；当前激活 ID 正则能够提取它。
- 该标识在本机支付卡缓存中没有精确匹配。
- 检查时 Mac 缓存有 12 条支付卡记录，未发现中国银行名称记录。
- 此次选中中国银行卡的操作窗口内，没有捕获到能对应此卡的可用卡片文件 ID。

```text
nfcd: ... setActivePaymentApplet ... requestedApplet:
      <NFApplet ... identifier=<UNMATCHED_ACTIVATION_ID> ...>
```

### 结论与待确认事项

支付激活标识和刷写所需的卡片文件 ID 是不同标识。`recordActivatedPaymentCard` 依赖缓存将前者映射到后者；本次映射缺失，因此无法建立对应槽位。

这不能证明卡片损坏、银联整体不受支持或 iOS 永远无法提供该 ID。当前证据只证明本次采集与现有缓存不足以完成映射。

- [ ] 仅在有新线索时检查其他明确包含卡片 ID 的手机事件或资源路径。
- [ ] 若仍没有可靠映射，明确报告未识别原因；不按卡片顺序、名称或卡号尾号猜测文件 ID。

## 界面与验证边界

- `0 payment entries` 表示 Mac 缓存没有剩余待确认的支付条目，不表示 iPhone 没有漏卡。
- `3f9ef23` 隐藏未经本轮观察的历史记录，但“日志提及资源路径”不等同于 Wallet 提供了权威的当前存在性确认。
- 本次采集发现了国泰的新解析线索，没有完成修复，也没有验证完全排除残留卡片。
- 后续预览或识别改动不能把缓存候选信息冒充手机当前状态。
