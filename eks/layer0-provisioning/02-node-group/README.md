# 02-node-group

**Reserved for additional managed node groups added later** (e.g. a dedicated
GPU/memory pool, or a Windows pool).

The **bootstrap `system` node group lives in `01-eks`**, inside the EKS module —
the module manages node Access Entries together with the cluster, so splitting
the first node group out adds IAM/access-entry plumbing for no benefit. Extra,
independent pools that reference the existing cluster belong here.

Empty until such a pool is needed.
