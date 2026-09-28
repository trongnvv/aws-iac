# ad-hoc

Throwaway experiments and lab deployments you run **on** a cluster — not part of the
platform's layers. Each subfolder is self-contained (its own manifests + README) and safe
to `kubectl delete -k .` when done.

Not to be confused with `../docs/hands-on/` — those are **guides** (how to get credentials,
push an image, walk through a deploy). This folder holds **deployable manifests**.

| Lab | What |
|---|---|
| `grpc-conn-debug/` | Shows the gRPC-on-L4-Service load-balancing gotcha (one pinned backend) and the fixes |
| `gp3-default-storageclass.yaml` | Default `gp3` StorageClass, applied post-cluster by the env's `deploy.sh` |
