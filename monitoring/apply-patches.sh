#!/bin/bash
# 监控组件补丁应用脚本
# 用途：当集群重建或配置丢失时，一键恢复所有手动调优的配置
# 用法：./apply-patches.sh

set -e

echo ">>> 应用 Grafana 探针与资源补丁..."
kubectl patch deployment prometheus-grafana -n monitoring \
  --type merge -f patches/grafana-probes-patch.yaml

echo ">>> 应用 Alertmanager 探针与资源补丁..."
kubectl patch statefulset alertmanager-prometheus-kube-prometheus-alertmanager -n monitoring \
  --type merge -f patches/alertmanager-probes-patch.yaml

echo ">>> 应用 Prometheus 命名空间选择器补丁..."
kubectl patch prometheus prometheus-kube-prometheus-prometheus -n monitoring \
  --type merge -f patches/prometheus-namespace-selector-patch.yaml

echo ">>> 所有补丁应用完成！"
echo ">>> 等待 Pod 滚动更新..."
sleep 5
kubectl get pods -n monitoring | grep -E "grafana|alertmanager|prometheus-prometheus"
