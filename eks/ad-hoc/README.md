# ad-hoc

Throwaway experiments and lab deployments you run **on** a cluster — not part of the
platform's layers. Each subfolder is self-contained (its own manifests + README) and safe
to `kubectl delete -k .` when done.

Not to be confused with `../docs/hands-on/` — those are **guides** (how to get credentials,
push an image, walk through a deploy). This folder holds **deployable manifests**.

| Lab | What |
|---|---|
| `gp3-default-storageclass.yaml` | Default `gp3` StorageClass, applied post-cluster by the env's `deploy.sh` |

> The gRPC LB lab moved to `envs/dev/03-application/00-grpc-debug/` (now a helm release via `charts/app`).
