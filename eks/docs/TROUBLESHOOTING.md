# EKS troubleshooting runbook

Symptom → likely cause → diagnose → fix, for the failures you actually hit on EKS. Assumes
`kubectl` + `aws` are wired (`hands-on/AWS-CREDENTIALS.md`). For the mechanics behind these
(auth planes, CNI IP allocation, node bootstrap) see [`MODULES.md`](MODULES.md).

## First-response toolkit (run these before guessing)
```bash
kubectl get nodes -o wide                      # node Ready? IPs? version skew?
kubectl get pods -A | grep -Ev 'Running|Completed'   # what's not healthy
kubectl describe pod <pod> -n <ns>             # Events at the bottom = the real story
kubectl logs <pod> -n <ns> --previous          # last crash's logs
kubectl get events -A --sort-by=.lastTimestamp | tail -30
aws eks describe-cluster --name <cluster> --query 'cluster.{status:status,health:health}'
aws eks list-addons --cluster-name <cluster>   # then describe-addon for health
```
> 90% of the time the answer is in `kubectl describe`'s **Events** section or the pod's
> **previous** logs. Look there first.

---

## 1. Node stuck `NotReady`
**Cause:** CNI not up (no pod IPs), kubelet can't reach the API, or the node role isn't
authorized.
**Diagnose:**
```bash
kubectl describe node <node>                    # Conditions: NetworkUnavailable? MemoryPressure?
kubectl -n kube-system get pods -o wide | grep aws-node   # CNI pod on that node Running?
kubectl -n kube-system logs -l k8s-app=aws-node --tail=50
aws ssm start-session --target <instance-id>    # then: sudo journalctl -u kubelet -n 100
```
**Fix:** aws-node `CrashLoopBackOff` → usually IAM (node role missing `AmazonEKS_CNI_Policy`)
or IP exhaustion (§3). kubelet "Unauthorized" registering → node role has **no `EC2_LINUX`
access entry** (rare in API mode; recreate the node group). NetworkUnavailable → security
group between control plane and nodes is blocking 443/10250.

## 2. Pod stuck `Pending`
**Cause:** no node has room / matches, or nothing is scaling nodes.
**Diagnose:**
```bash
kubectl describe pod <pod> -n <ns>              # Events: "0/N nodes available: Insufficient cpu" / taints / affinity
kubectl -n kube-system logs -l app.kubernetes.io/name=karpenter --tail=50   # is Karpenter reacting?
```
**Fix:** `Insufficient cpu/memory` + Karpenter not launching → §12. Taint mismatch → add a
toleration or fix the NodePool. `didn't match node selector` → wrong `nodeSelector`/affinity.
No capacity in AZ → widen instance types / AZs in the NodePool.

## 3. Pod stuck `ContainerCreating` — IP exhaustion (CNI)
**Cause:** the app subnet ran out of IPs, or the node hit max-pods.
**Diagnose:**
```bash
kubectl describe pod <pod> -n <ns>             # Events: "failed to assign an IP address to container"
aws ec2 describe-subnets --subnet-ids <app-subnet> \
  --query 'Subnets[].AvailableIpAddressCount'
kubectl -n kube-system logs -l k8s-app=aws-node | grep -i "no available ip"
```
**Fix:** short term — free IPs / smaller pods. Real fix — **prefix delegation** (already on
here: `ENABLE_PREFIX_DELEGATION=true`) and/or a **secondary CIDR** with custom networking
(`6-secondary-cidr.tf`). Right-size the `/20` app subnets for peak pods; each `/28` prefix
reserves 16 IPs. See MODULES.md §4.

## 4. Pod stuck `ContainerCreating` — volume won't attach (EBS CSI)
**Cause:** EBS CSI driver can't create/attach the volume (IAM, AZ mismatch, or driver down).
**Diagnose:**
```bash
kubectl describe pod <pod> -n <ns>             # "FailedAttachVolume" / "FailedMount"
kubectl get pvc -n <ns>                        # Bound? or Pending?
kubectl -n kube-system logs -l app=ebs-csi-controller -c ebs-plugin --tail=50
```
**Fix:** IAM → EBS-CSI role missing `AmazonEBSCSIDriverPolicy` or Pod Identity association
broken (MODULES.md §6). **AZ mismatch** → an EBS volume can only attach in its own AZ; a
pod rescheduled to another AZ can't mount it — use `WaitForFirstConsumer` on the
StorageClass (gp3 default here already does). KMS → the CSI role needs `kms:CreateGrant` on
the volume key.

## 5. DNS resolution failing inside pods
**Cause:** CoreDNS unhealthy, or the CNI/NetworkPolicy is dropping DNS.
**Diagnose:**
```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns          # CoreDNS Running?
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=50
kubectl run dnstest --rm -it --image=busybox:1.36 --restart=Never -- nslookup kubernetes.default
```
**Fix:** CoreDNS `Pending` → no nodes yet (§2). Intermittent under load → the managed
coredns add-on's `autoScaling` (on here) or NodeLocal DNSCache (`layer1/09-dns-scale`).
Blocked → a NetworkPolicy without a UDP/53 egress allow to kube-system. `kube-proxy` down →
Service ClusterIP (incl. `kube-dns` 10.x.x.10) won't route.

## 6. `Unauthorized` / "You must be logged in to the server"
**Cause:** IAM authenticated but no K8s authorization — the two auth planes disagree.
**Diagnose:**
```bash
aws sts get-caller-identity                     # WHICH principal am I? (note the role ARN)
aws eks list-access-entries --cluster-name <cluster>
```
**Fix:** add your principal's ARN to `admin_principal_arns` in `envs/<env>/01-eks/main.tf`
and apply — it becomes an Access Entry with `AmazonEKSClusterAdminPolicy`. **Use the SSO
permission-set role ARN, not `:root`** (`:root` is invalid for an access entry). This is
API auth mode → there is **no `aws-auth` ConfigMap** to edit. Kubeconfig pointing at the
wrong cluster/profile also shows this — re-run `aws eks update-kubeconfig`.

## 7. Managed add-on `Degraded` / `Create failed`
**Cause:** version incompatible with the K8s minor, config conflict, or no nodes to run on.
**Diagnose:**
```bash
aws eks describe-addon --cluster-name <cluster> --addon-name <name> \
  --query 'addon.{status:status,health:health.issues}'
```
**Fix:** coredns/kube-proxy `Degraded` on a brand-new cluster = **no nodes yet**, resolves
after the node group is up (expected — MODULES.md §1). Version error → pick a version valid
for the cluster's minor (`aws eks describe-addon-versions`). `ConfigurationConflict` →
something edited the add-on's objects out-of-band; set `resolve_conflicts=OVERWRITE` or stop
hand-editing managed objects.

## 8. `Service type=LoadBalancer` / Ingress — no ALB/NLB appears
**Cause:** AWS Load Balancer Controller isn't installed, lacks IAM, or subnets aren't tagged.
**Diagnose:**
```bash
kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl -n kube-system logs -l app.kubernetes.io/name=aws-load-balancer-controller --tail=80
kubectl describe ingress <ing> -n <ns>          # Events: subnet discovery / auth errors
```
**Fix:** LBC is **Helm (layer1/02)**, not a managed add-on — install it. IAM → its Pod
Identity role needs the LBC policy (`addon-iam` module). **Subnet tags** are mandatory:
public subnets `kubernetes.io/role/elb=1`, private `kubernetes.io/role/internal-elb=1`
(set by `modules/network`). No `ingressClassName: alb` / wrong annotations → LBC ignores it.

## 9. `ImagePullBackOff` / `ErrImagePull`
**Cause:** wrong image ref, no pull permission, or no network path to the registry.
**Diagnose:**
```bash
kubectl describe pod <pod> -n <ns>              # "pull access denied" vs "no such host" vs "not found"
aws ecr describe-images --repository-name <repo> --region ap-southeast-1 \
  --query 'imageDetails[].imageTags'            # does the tag actually exist?
```
**Fix:** ECR same-account → node role has `AmazonEC2ContainerRegistryReadOnly`, no
imagePullSecret needed. Cross-account → add an ECR **repository policy** for the other
account's node role. `no such host` on a private cluster → missing **ECR + S3 VPC
endpoints** (`modules/network` provides them; ECR layers come from S3). Tag not found →
immutable repo, you pushed a different tag (`PUSH-IMAGE-TO-ECR.md`).

## 10. `exec format error` on start
**Cause:** image architecture ≠ node architecture.
**Diagnose:**
```bash
kubectl get nodes -o jsonpath='{.items[*].status.nodeInfo.architecture}'   # arm64 here
docker manifest inspect <image> | grep architecture
```
**Fix:** nodes are **arm64 (Graviton t4g/m7g)** — build `linux/arm64` or multi-arch
(`docker buildx --platform linux/amd64,linux/arm64`). See `PUSH-IMAGE-TO-ECR.md` §3.

## 11. API endpoint unreachable (`i/o timeout`, `no route to host`)
**Cause:** private endpoint reached from outside the VPC, or SG/DNS misconfig.
**Diagnose:**
```bash
aws eks describe-cluster --name <cluster> \
  --query 'cluster.resourcesVpcConfig.{public:endpointPublicAccess,private:endpointPrivateAccess,cidrs:publicAccessCidrs}'
nslookup <cluster-endpoint>                     # resolves to private IPs? then you must be in-VPC
```
**Fix:** **prod uses a private endpoint** → run kubectl/deploy from **inside the VPC**
(bastion, VPN, or SSM port-forward). Public-but-restricted → your egress IP isn't in
`publicAccessCidrs`. Private DNS must be enabled on the VPC for the endpoint to resolve.

## 12. Karpenter not scaling up (pods Pending, no nodes launch)
**Cause:** controller can't launch EC2 — IAM, discovery tags, or NodePool limits.
**Diagnose:**
```bash
kubectl -n kube-system logs -l app.kubernetes.io/name=karpenter --tail=100   # RunInstances errors?
kubectl get nodepool,ec2nodeclass -o wide
kubectl describe ec2nodeclass <name>            # subnet/SG discovery found anything?
```
**Fix:** `UnauthorizedOperation` → controller Pod Identity role missing `ec2:RunInstances`/
`CreateFleet` (`karpenter-infra` + controller role). **Discovery** → subnets/SGs must carry
`karpenter.sh/discovery=<cluster>` (set by `modules/network` + `modules/eks`
`node_security_group_tags`). NodePool `limits` reached, or no instance type satisfies the
pod's requests/AZ. Missing instance profile → JIT nodes can't assume the node role.

## 13. Pod can't get AWS credentials (Pod Identity / IRSA)
**Cause:** no association, agent down, or SDK too old.
**Diagnose:**
```bash
kubectl -n kube-system get pods -l app.kubernetes.io/name=eks-pod-identity-agent -o wide
aws eks list-pod-identity-associations --cluster-name <cluster>
kubectl exec <pod> -n <ns> -- env | grep AWS_CONTAINER_CREDENTIALS   # injected?
```
**Fix:** create the association (SA↔role) — `addon-iam` module does this per add-on. Agent
`CrashLoop` or not on the node → pods can't reach `169.254.170.23`. `AccessDenied` after
creds arrive → the role's **policy** is too narrow, not an identity problem. Very old AWS
SDK → doesn't support the Pod Identity endpoint; use IRSA or upgrade the SDK.

## 14. Node launches but never joins the cluster
**Cause:** bootstrap (`nodeadm`) failed — bad cluster data, no API path, or no auth.
**Diagnose:**
```bash
aws autoscaling describe-scaling-activities --auto-scaling-group-name <mng-asg> --max-items 5
aws ssm start-session --target <instance-id>
  sudo journalctl -u kubelet -n 100
  sudo nodeadm debug            # AL2023: checks endpoint/CA/API reachability
```
**Fix:** `nodeadm` can't reach the API → node SG / route to the endpoint ENIs is blocked, or
private endpoint with no in-VPC DNS. Wrong cluster name/CA in user-data → recreate the node
group so the launch template is regenerated. Node role not mapped → API auth mode
auto-creates the `EC2_LINUX` entry; if it's missing, the node group wasn't created through
the module.

## 15. `tofu apply`/`destroy` hangs on the cluster or VPC
**Cause:** dependency ordering — orphaned ENIs/ELBs from in-cluster controllers.
**Diagnose:**
```bash
aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=<vpc> \
  --query 'NetworkInterfaces[?Status==`in-use`].[NetworkInterfaceId,Description]' --output table
kubectl get svc,ingress -A          # any type=LoadBalancer still up?
```
**Fix:** **destroy the LB Controller and its ALBs/NLBs before the VPC** — `scripts/teardown.sh`
does this in order (removes ingress → ELBs → ENIs, then VPC). Stuck cluster create → check
`describe-cluster` `health.issues` (bad subnet/role). Leftover Karpenter nodes → they aren't
in tofu state; delete NodeClaims / terminate instances before destroying `00-network`.
