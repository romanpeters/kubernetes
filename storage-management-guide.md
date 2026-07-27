# K3s Storage Management Guide

## Overview
This document outlines strategies for managing storage pressure in the K3s cluster, particularly the ephemeral storage issue affecting cleanuparr and calibre-web pods.

## Immediate Actions
1. Monitor ephemeral storage usage with:
   ```
   kubectl top nodes
   ```

2. Check individual pod storage usage:
   ```
   kubectl describe pod <pod-name> -n media
   ```

3. Clean up old evicted pods as needed:
   ```
   kubectl delete pod -n media --field-selector=status.phase=Failed
   ```

## Configuration Improvements

### Resource Limits for Storage Intensive Apps
Applications with high ephemeral storage needs should use conservative limits:

```yaml
resources:
  limits:
    ephemeral-storage: "500Mi"
  requests:
    ephemeral-storage: "250Mi"
```

This ensures pods don't consume all available ephemeral storage space and helps prevent eviction.

### Log Management Strategy
- Implement log rotation for all applications in the media namespace
- Limit log retention to 7 days or 500MB per pod
- Use structured logging that can be aggregated and rotated properly

## Monitoring Alerts Required
Create alerts for:
1. Node ephemeral storage usage > 85%
2. Pod ephemeral storage consumption > 400Mi
3. Disk pressure conditions in node status

This approach prevents the pod eviction issue while maintaining operational efficiency.
