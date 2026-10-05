# 独立安装助手验收

发布包在 `Contents/Helpers/PrismUpdateInstaller` 内包含原生 Universal 助手。助手与外层应用分别签名；公测继续使用 ad hoc 签名。助手只使用系统框架，不依赖 Sparkle，也不提升权限或更改系统全局安全设置。

助手再次验证同一临时 workspace 的 Ed25519 更新签名、六字段 manifest、DMG 实际 SHA-256 与字节数。它重新只读挂载已验证的 DMG，从这个归档复制应用到目标同目录的 staging 包，再检查应用身份、版本、最低系统版本、完整代码签名与路径。它不信任此前解出的临时应用。

1.14.3 起，每次更新弹窗的 `allowUnnotarizedPublicTestUpdate` 默认关闭，不跨弹窗保存。只有用户明确勾选、助手独立验签与 staging 校验通过、原父进程退出且最终 commit 有效时，才在替换前对该 staging 包执行 `xattr -dr com.apple.quarantine`。下载文件、准备阶段的临时应用和原应用均不受影响。未勾选或旧计划缺字段时保留隔离标记；取消及验证失败不会移除。失败回滚和运行进程身份认证仍执行。

主应用与助手的协议文件位于权限 0700 的 `installation-UUID` 目录，计划与握手文件权限 0600。助手核对当前进程的实际可执行路径、UID 和内核微秒出生时间，先写 `ready`，然后等待原父进程退出。主应用只有通过最终持久化与链接接收门禁后才写 UUID 内容的 `commit` 文件。父退出但没有正确 commit、PID 复用、取消或等待超时都不替换应用。

替换采用同目录备份旧包、移动新包、LaunchServices 指定目标启动并验证返回进程可信代码身份的事务；失败恢复旧包并尝试打开。原备份只有在新版完成启动、持续运行两秒且动态代码认证通过后才清理。恢复失败保留备份并在 receipt 中写明位置；启动成功并不证明业务功能全部正常。receipt 保留在临时控制目录，结果为 installed、cancelled、failed、rolledBack 或 recoveryRequired。

## 自动行为测试

`UpdateInstallationTests` 仅操作临时合成目录，覆盖目标逃逸、嵌套符号链接、只读卷路径、等待超时、PID 复用、复制失败、移动失败、启动失败、取消、成功、既有 staging 不被误删、严格升版，以及没有最终 commit 时禁止替换。隔离标记回归使用真实文件扩展属性，覆盖计划缺字段、false 与 true；session 测试确认新弹窗默认关闭、安装时传递用户选择。

`UpdateArchiveVerificationTests` 使用临时 Ed25519 fixture key，覆盖合法签名、manifest 篡改、DMG 同长度篡改、字节数不符、已签名但版本/身份/文件名/最低系统不符及符号链接。生产助手不提供运行时信任密钥或身份覆盖参数。

## 实际替换与重启验收

不要用 `/Applications/Prism.app` 或当前用户实际应用作为目标。不要为测试修改默认浏览器或用户规则/历史。因为相同 bundle ID 的临时应用也可能被 LaunchServices 登记，实际重启验收必须采用独立的测试身份。

单独以 `DEBUG && PRISM_UPDATE_QA` 编译同一助手源码，固定测试身份为 `com.prism.iterationqa.update`；发行配置始终固定 `com.prism.app`。测试用 AppKit 应用只显示版本与验收按钮，写临时 workspace 的启动标记，没有 URL handler 和生产配置读取。fixture 的 DMG 由独立 Ed25519 测试密钥签名，仅仓库外 QA 助手副本编译时嵌入测试公钥；发行源码与公钥不变。助手仍执行同一签名、挂载、stage、最终 commit、替换、启动及回滚逻辑。

临时 fixture 源码与构建脚本位于仓库外，不作为产品打包输入。启动隔离身份的临时 `Prism.app`，使用权限受控的新 plan 在助手启动前传入公测许可；看到 ready 后先确认旧应用仍运行且 staging 保留隔离标记。最终 commit 后退出旧应用，检查目标版本变更、候选窗口、新 PID、启动标记、receipt、备份清理和磁盘映像卸载。未许可的取消轮次应看到旧应用继续运行、cancelled receipt、原包保留；篡改签名或归档不能进入替换阶段。不修改全局 Gatekeeper 设置。

## 系统保护位置与进程身份

正常运行的实例仍要求当前实际可执行位置与目标一致。系统从只读保护位置运行新版时，助手通过 Security 的内核 guest、实际运行架构 CDHash、完整 Universal 主可执行文件 SHA-256、全部架构与嵌套资源签名、封存 Info.plist 身份和版本证明运行的是可信目标代码；PID、UID 和微秒出生时间在验证前后保持一致。不会仅凭路径含 AppTranslocation、相同应用名称或相同版本放行。旧目标身份在父进程验证前固定，验证后和父进程退出后再次核对，并在移动前重新确认版本递增。

重新启动时仅传递原安装路径这一环境提示，不传递助手全部环境。新版只有在实际内核可执行位置处于只读保护位置、正常原目标可写且动态代码核对全部通过时，才接受原位置用于后续更新；正常位置运行的实例拒绝指向其它副本的环境提示。没有可验证原位置的保护实例保留手动安装入口。未允许公测例外，或仍受其他系统策略限制时，启动失败会恢复原应用。公测许可不等于 Apple Developer ID 或公证。

实际 Universal fixture 验收覆盖主机架构的真实运行与两个架构的完整签名，不能代替 Rosetta 或 Intel 实机运行验收。

## 1.14.3 公测许可验收

2026-10-05 的六轮检查使用最小独立 AppKit fixture：许可为 true 后成功替换、启动新 PID 并动态认证新版本；缺省与 false 在 ready 时保留 staging 根及可执行文件隔离标记，取消后旧版完整；同长度 DMG 篡改或签名篡改均在 ready 前失败，未产生 staging 或替换；新版启动后提前退出时，恢复并真实启动旧版，动态认证与 rolledBack 回执一致。全部 QA 进程、挂载及临时私钥已清理。运行验证限本机 arm64，不能代替完整产品 UI 或 Intel 验收。
