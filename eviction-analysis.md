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

4. Set up automated cleanup processes via CronJobs to prevent future accumulation of unused containers/images (see k3s-storage-cleanup.md)

## Storage Management Best Practices
Applications in the cluster should have appropriate resource limits set, especially for ephemeral storage. This ensures pods don't consume all available ephemeral storage space and helps prevent eviction.

For resources that may need more space based on their nature:
- cleanuparr: Currently 300Mi limit (this may need to be increased per usage patterns)
- calibre-web: Should have proper limits set as well

## Implementation Plan (GitOps Compliant)
1. Add monitoring to detect ephemeral storage usage by pods
2. Create cleanup processes scheduled via CronJobs (automated cleanup jobs already defined in k3s-storage-cleanup.md)
3. Set up alerting with the monitoring stack for storage pressure

## Commands to execute immediately:
kubectl delete pod -n media <evicted-pod-name>
kubectl describe nodes
kubectl get pods -A --field-selector=status.phase=Failed
```
