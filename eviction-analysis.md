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
       ephemeral-storage: "500Mi"
     requests:
       ephemeral-storage: "250Mi"
   ```

2. Monitor disk usage with `kubectl top nodes` and set up alerts for ephemeral storage

3. Implement log rotation or retention policies for applications in media namespace

## Implementation Plan (GitOps Compliant)
1. Add monitoring to detect ephemeral storage usage by pods
2. Create cleanup processes scheduled via CronJobs
3. Set up alerting with the monitoring stack for storage pressure

## Commands to execute immediately:
kubectl delete pod -n media <evicted-pod-name>
kubectl describe nodes
kubectl get pods -A --field-selector=status.phase=Failed
```
