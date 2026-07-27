# K3s Cluster Storage Cleanup Configuration

This file contains configurations to help with storage cleanup in K3s clusters to prevent disk pressure issues.

## Purpose
To configure cleanup procedures that automate routine maintenance tasks that prevent pods from being evicted due to ephemeral storage exhaustion.

## Automated Cleanup Jobs

### Cleanup Script for Container Runtime
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: k3s-container-cleanup
  namespace: kube-system
spec:
  schedule: "0 2 * * 0"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: cleanup
            image: alpine:latest
            command:
            - /bin/sh
            - -c
            - |
              echo "Running K3s container cleanup"
              # Remove unused containers and images
              apk add --no-cache docker-cli
              docker system prune -af --filter until=24h 2>/dev/null || true
              echo "Cleanup completed"
          restartPolicy: OnFailure
```

## Manual Storage Health Check Commands

To check current storage health:
```bash
kubectl describe nodes
kubectl get pods -A --field-selector=status.phase!=Running | grep -v Completed
kubectl top nodes
```

This configuration should be applied to the cluster through the GitOps workflow where it will be managed automatically.
