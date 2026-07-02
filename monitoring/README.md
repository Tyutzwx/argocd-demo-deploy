# 监控栈定制配置

## 背景
监控栈（kube-prometheus-stack）通过 Helm 手动部署，不在 ArgoCD 管辖范围内。
以下是排查和修复监控组件高频重启问题（Exit Code 255）时，手动 `kubectl patch` 的固化记录。

## 补丁文件说明
| 文件 | 作用 |
|------|------|
| `patches/grafana-probes-patch.yaml` | Grafana: 探针延时从1s→10s，内存从256Mi→512Mi |
| `patches/alertmanager-probes-patch.yaml` | Alertmanager: 探针延时调优，内存升至512Mi |
| `patches/prometheus-namespace-selector-patch.yaml` | Prometheus: 允许监控所有命名空间的 ServiceMonitor |

## 应用补丁（集群重建后恢复配置）
```bash
cd monitoring && ./apply-patches.sh
```

## 验证补丁是否生效
```bash
kubectl get deployment prometheus-grafana -n monitoring -o yaml | grep -A5 livenessProbe
kubectl get statefulset alertmanager-prometheus-kube-prometheus-alertmanager -n monitoring -o yaml | grep -A5 livenessProbe
```
