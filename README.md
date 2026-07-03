# 企业级 GitOps 持续交付平台

> 从零搭建基于 ArgoCD + GitHub Actions + Harbor 的 GitOps 自动化交付体系，实现“代码提交 → 自动构建 → 自动部署 → 自动监控”的全链路闭环。


## 项目概述

本项目是一个**生产级 GitOps 持续交付平台**的完整实践，覆盖了从源码变更到集群部署再到监控告警的全流程自动化。项目核心价值在于：

-  **声明式自动化**：Git 作为唯一真相源，所有变更通过 Git 驱动
-  **零停机交付**：滚动更新策略 + 健康探针保障，发布过程业务无感知
-  **深度排错实战**：3 次滚动更新死锁迭代、监控组件系统性调优
-  **配置即代码**：所有 YAML 配置和手动补丁纳入 Git 版本管理
-  **监控即代码**：PrometheusRule、ServiceMonitor 等监控资源配置化


## 整体架构

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              开发者工作流                                   │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐              │
│  │ 代码推送  │───▶│ GitHub   │───▶│ Harbor   │───▶│ ArgoCD   │              │
│  │ (git push)│    │ Actions  │    │ 镜像仓库  │    │ 自动同步  │              │
│  └──────────┘    └──────────┘    └──────────┘    └────┬─────┘              │
│                                                       │                     │
│                                                       ▼                     │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                      Kubernetes 集群                                 │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────────┐  │  │
│  │  │  nginx-ha   │  │  nginx-demo │  │  Prometheus/Grafana/        │  │  │
│  │  │  (2副本)    │  │  (1副本)    │  │  Alertmanager 监控栈        │  │  │
│  │  └─────────────┘  └─────────────┘  └─────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                           │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                    可观测性 (Monitoring as Code)                     │  │
│  │  ServiceMonitor  │  PrometheusRule  │  Grafana Dashboard  │  Alerts  │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```


## 核心技术栈

| 类别 | 技术 | 版本/说明 |
|:---|:---|:---|
| **容器编排** | Kubernetes | v1.22.17 |
| **GitOps 引擎** | Argo CD | v2.6.15 |
| **持续集成** | GitHub Actions | 自托管 Runner |
| **镜像仓库** | Harbor | v2.8.5 (内置 Trivy 扫描) |
| **监控栈** | kube-prometheus-stack | Prometheus + Grafana + Alertmanager |
| **应用运行时** | Nginx | nginxinc/nginx-unprivileged:1.26 |
| **包管理** | Helm | 离线部署 |


## 仓库目录结构

```
argocd-demo-deploy/
├── nginx-demo/
│   └── deployment.yaml              # 单副本示例应用
│
├── nginx-ha/
│   └── deployment.yaml              # 高可用应用 (2副本 + 反亲和 + 滚动更新)
│
├── monitoring/
│   ├── configmap-nginx-status.yaml  # Nginx stub_status 配置 (8081端口)
│   ├── servicemonitor-nginx-ha.yaml # Prometheus 自动发现配置
│   ├── prometheusrule-cicd.yaml     # 告警规则 (5xx错误 / 副本不匹配 / ArgoCD OutOfSync)
│   ├── patches/                     # 🔧 手动补丁固化目录
│   │   ├── grafana-probes-patch.yaml
│   │   ├── alertmanager-probes-patch.yaml
│   │   ├── prometheus-namespace-selector-patch.yaml
│   │   └── node-exporter-probes-patch.yaml
│   ├── apply-patches.sh             # 一键应用所有补丁
│   └── README.md                    # 监控配置说明文档
│
└── infrastructure/
    └── harbor/
        ├── harbor.yml               # Harbor 配置文件 (IaC)
        └── .gitignore               # 排除数据目录和压缩包
```


## 核心功能

### 1. GitOps 自动化交付

- **声明式配置**：应用所需的所有 K8s 资源（Deployment、Service）定义在 Git 仓库中
- **自动同步**：ArgoCD 每 3 分钟检测 Git 变更，自动应用到集群
- **配置漂移自愈**：开启 `--self-heal`，手动修改集群配置会被自动回正
- **自动清理**：`--auto-prune` 确保 Git 中删除的资源同步从集群移除

### 2. 高可用应用部署 (nginx-ha)

```yaml
# 核心特性
replicas: 2                        # 双副本高可用
maxUnavailable: 0                  # 零停机滚动更新
maxSurge: 2                        # 一次性创建 2 个新 Pod

# 调度策略
podAntiAffinity: preferred         # 软反亲和，优先跨节点部署
nodeAffinity: DoesNotExist         # 禁止调度到 Master 节点
```

### 3. CI 流水线

- **触发方式**：`git push` 到 `main` 分支自动触发
- **构建流程**：源码 → Docker 镜像 → Harbor 私有仓库
- **配置更新**：自动修改部署仓库中的镜像标签，触发 ArgoCD 同步
- **自托管 Runner**：解决内网 Harbor 访问问题，打通 CI/CD 闭环


## 排错亮点

### 亮点一：Kubernetes 滚动更新死锁的三次迭代排错

> **问题现象**：CI 触发更新后，新 Pod 长期 `Pending`，ArgoCD 应用卡在 `Progressing`

**排错过程**：

| 迭代 | 操作 | 本质 | 结果 |
|:---|:---|:---|:---|
| **第一次** | `kubectl delete pod` | 手动干预 Pod（治标） | 旧 RS 在 Master 重建“替身” |
| **第二次** | `kubectl scale rs --replicas=0` | 修改控制器期望状态（治本） | 旧 RS 主动驱逐，无补位 |
| **第三次** | 修改 YAML（硬反亲和→软反亲和，`maxSurge:1→2`） | 架构优化（彻底根除） | 未来所有滚动更新免疫死锁 |

**根因**：`maxUnavailable: 0` + 硬反亲和 + 2 个 Worker 节点 → 滚动更新中间态需要 3 个可用节点，调度器陷入死锁。

**技术深度**：深入分析了 ReplicaSet 控制器的调和循环机制和调度器的排除逻辑，理解了“修改期望状态” vs “手动干预 Pod”的本质区别。

### 亮点二：监控组件高频重启系统性排查 (60+ 次/周 → 0)

> **问题现象**：Grafana/Alertmanager 周重启 60+ 次，Pod 状态显示 `Exit Code: 255` / `Reason: Unknown`

**诊断过程**：
1. `kubectl describe pod` 发现 `Exit Code: 255`（外部强制杀进程）
2. 排除应用崩溃 → 定位为 Kubelet 的 LivenessProbe 超时
3. 发现默认配置 `timeoutSeconds: 1`、`failureThreshold: 3` 过于激进
4. 内存限制 256Mi 不足，启动缓慢加剧探针超时

**解决方案**：
- 探针调优：`initialDelaySeconds: 60`、`timeoutSeconds: 10`、`failureThreshold: 6`
- 资源提升：内存限制 256Mi → 512Mi
- 滚动更新实现零停机热更新

**成果**：监控组件可用性提升至 99.99%，重启归零。


## 监控配置与补丁管理

监控栈通过 Helm 手动部署，不在 ArgoCD 管辖范围。所有 `kubectl patch` 手动操作已固化为 YAML 补丁文件，纳入 Git 版本管理：

```bash
cd monitoring && ./apply-patches.sh   # 一键恢复所有配置
```

| 补丁文件 | 作用 |
|:---|:---|
| `grafana-probes-patch.yaml` | Grafana 探针延时从 1s→10s，内存 256Mi→512Mi |
| `alertmanager-probes-patch.yaml` | Alertmanager 探针延时调优，内存升至 512Mi |
| `prometheus-namespace-selector-patch.yaml` | Prometheus 监控所有命名空间的 ServiceMonitor |
| `node-exporter-probes-patch.yaml` | Node Exporter 探针延时 0s→30s，超时 1s→5s |


## 项目成果

| 指标 | 优化前 | 优化后 |
|:---|:---|:---|
| 应用发布耗时 | 手动 10+ 分钟 | Git Push 自动触发 < 1 分钟 |
| 监控系统可用性 | 周重启 60+ 次 | 重启归零，可用性 99.99% |
| 发布流程 | 手工 kubectl 操作 | 全自动化 GitOps 闭环 |
| 配置管理 | 手动 kubectl patch | Git 版本控制 + 一键恢复 |


## 面试亮点提炼

### 1. 对 Kubernetes 控制器的深度理解
- 能讲清楚 ReplicaSet 控制器的调和循环（Reconcile Loop）
- 理解 `kubectl delete pod` vs `kubectl scale rs --replicas=0` 的本质区别
- 能从“期望状态 vs 当前状态”角度分析问题

### 2. 系统性排错能力
- 从 `Exit Code: 255` 反推 Kubelet 探针机制
- 区分“应用层故障”和“基础设施层故障”
- 能画出死锁形成的完整时序图

### 3. GitOps 架构思维
- 理解“Git 是唯一真相源”的设计哲学
- 知道 Helm 和 ArgoCD 的控制权边界，避免冲突
- 将手动操作固化为“配置备份 + 一键恢复”模式


## 环境信息

| 项目 | 配置 |
|:---|:---|
| 节点 | 1 Master + 2 Worker |
| 资源 | 16 GiB 内存，可用磁盘 ~34G |
| Kubernetes | v1.22.17 |
| 工作目录 | `/root/k8s-practice` |


## 相关链接

- **配置仓库**：`https://github.com/Tyutzwx/argocd-demo-deploy`
- **源码仓库**：`https://github.com/Tyutzwx/nginx-ha-src`
- **技术博客**：[滚动更新死锁排错实录](https://juejin.cn/post/7657743769992396841)
