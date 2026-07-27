# Kubernetes Eviction Analysis for cleanuparr and calibre-web

## Problem Statement
The cluster is experiencing persistent eviction issues with cleanuparr and calibre-web pods due to ephemeral storage exhaustion. Both applications are failing with "Evicted" status because of disk pressure conditions on the node.

## Root Cause
- Node has DiskPressure condition (DiskPressure=True)
- Cleanuparr and calibre-web pods are consistently being evicted
- Applications are not limiting their ephemeral storage usage
- Log accumulation in local path provisioner volumes

## Immediate Solutions
1. Set proper ephemeral-storage limits for cleanuparr and calibre-web deployments
2. Clean up existing evicted pods to reduce storage pressure
3. Implement a cleanup process for these applications

## Long-term Solutions
1. Set resource limits on ephemeral storage:
   ```yaml
   resources:
     limits:
       ephemeral-storage: "5Gi"
     requests:
       ephemeral-storage: "2Gi"
   ```

2. Monitor disk usage with `kubectl top nodes` and set up alerts

3. Implement log rotation or retention policies for applications in media namespace

## Commands to execute immediately:
kubectl delete pod -n media <evicted-pod-name>
kubectl describe nodes
kubectl get pods -A --field-selector=status.phase=Failed
```
