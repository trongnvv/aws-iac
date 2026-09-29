# Test — Transit Gateway vs VPC Lattice

Two ways to connect the `dev` VPC to another VPC: **Transit Gateway** (L3/L4 —
route tables, any protocol) vs **VPC Lattice** (L7 — service networking via the
Gateway API, no route tables). Same `whoami` app from
`01-TEST-INGRESS-GATEWAY-API.md` §1, reached from outside its VPC both ways.

> 💸 TGW: `$0.05/h` per attachment (2 here) + `$0.02/GB` processed. VPC Lattice:
> `$0.025/h` per service + `$0.025/GB` + `$0.10`/million requests over a 300k/h
> free tier. Both trivial for a short test; clean up (§4/§5) when done.

## 0. Prereqs
- `dev` cluster up (`docs/DEPLOY.md`), `whoami` REST app from
  `01-TEST-INGRESS-GATEWAY-API.md` §1 running (`kubectl get deploy whoami`).
- A throwaway **"partner" VPC** — a stand-in for an external network, not part of
  this repo's IaC (ad hoc, plain AWS CLI, like the CI/CD tests' throwaway repos):
```bash
PARTNER_VPC=$(aws ec2 create-vpc --cidr-block 10.99.0.0/24 --query Vpc.VpcId --output text)
aws ec2 create-tags --resources "$PARTNER_VPC" --tags Key=Name,Value=partner-lab
PARTNER_SUBNET=$(aws ec2 create-subnet --vpc-id "$PARTNER_VPC" --cidr-block 10.99.0.0/26 \
  --availability-zone ap-southeast-1a --query Subnet.SubnetId --output text)
PARTNER_IGW=$(aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$PARTNER_IGW" --vpc-id "$PARTNER_VPC"
PARTNER_RT=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$PARTNER_VPC" \
  --query 'RouteTables[0].RouteTableId' --output text)
aws ec2 create-route --route-table-id "$PARTNER_RT" --destination-cidr-block 0.0.0.0/0 --gateway-id "$PARTNER_IGW"
PARTNER_SG=$(aws ec2 create-security-group --group-name partner-lab --vpc-id "$PARTNER_VPC" \
  --description "partner lab" --query GroupId --output text)
aws ec2 authorize-security-group-egress --group-id "$PARTNER_SG" --protocol -1 --cidr 0.0.0.0/0 2>/dev/null || true
INSTANCE=$(aws ec2 run-instances --image-id "$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text)" \
  --instance-type t3.micro --subnet-id "$PARTNER_SUBNET" --security-group-ids "$PARTNER_SG" \
  --associate-public-ip-address --query 'Instances[0].InstanceId' --output text)
```
This "partner" EC2 is the far side for both cases below — same role as the
exchange/partner boxes `docs/NETWORKING.md` §2 talks about allowlisting.

## 1. Case A — Transit Gateway (L3/L4)
```bash
TGW=$(aws ec2 create-transit-gateway --description "lab-tgw" \
  --query TransitGateway.TransitGatewayId --output text)
DEV_VPC=$(cd ../../../../envs/dev/00-infra/00-network && tofu output -raw vpc_id)
DEV_APP_SUBNETS=$(cd ../../../../envs/dev/00-infra/00-network && tofu output -json app_subnet_ids | jq -r '.[0]')

aws ec2 create-transit-gateway-vpc-attachment --transit-gateway-id "$TGW" \
  --vpc-id "$DEV_VPC" --subnet-ids "$DEV_APP_SUBNETS"
aws ec2 create-transit-gateway-vpc-attachment --transit-gateway-id "$TGW" \
  --vpc-id "$PARTNER_VPC" --subnet-ids "$PARTNER_SUBNET"
# wait for both attachments to reach "available" (aws ec2 describe-transit-gateway-attachments)
```
Both VPCs auto-associate to the TGW's default route table (propagation on by
default) — add the return routes on each side:
```bash
DEV_APP_RT=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$DEV_VPC" "Name=tag:Name,Values=*app*" \
  --query 'RouteTables[0].RouteTableId' --output text)
aws ec2 create-route --route-table-id "$DEV_APP_RT" --destination-cidr-block 10.99.0.0/24 --transit-gateway-id "$TGW"
aws ec2 create-route --route-table-id "$PARTNER_RT" --destination-cidr-block 10.0.0.0/16 --transit-gateway-id "$TGW"
```
Open the path in security groups — the cluster's shared SG (both ALB/LBC-managed
pods and the control plane use it) needs an inbound rule from the partner CIDR:
```bash
CLUSTER_SG=$(cd ../../../../envs/dev/00-infra/01-eks && tofu output -raw cluster_security_group_id)
aws ec2 authorize-security-group-ingress --group-id "$CLUSTER_SG" \
  --protocol tcp --port 80 --cidr 10.99.0.0/24
```
Expose `whoami` on a routable IP — pod IPs are real ENI IPs (`target-type ip`,
same as the ALB pattern) but ephemeral; use an **internal NLB** instead, same as
`docs/NETWORKING.md`'s "Internal ALB/NLB + PrivateLink" option:
```bash
kubectl expose deployment whoami --name whoami-internal --port=80 --type=LoadBalancer \
  --overrides '{"metadata":{"annotations":{"service.beta.kubernetes.io/aws-load-balancer-type":"nlb","service.beta.kubernetes.io/aws-load-balancer-scheme":"internal","service.beta.kubernetes.io/aws-load-balancer-nlb-target-type":"ip"}}}'
kubectl get svc whoami-internal -w   # wait for the NLB hostname
```
From the partner EC2 (SSM Session Manager or its public IP):
```bash
curl "$(kubectl get svc whoami-internal -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```
The NLB's AWS-generated DNS name resolves to **private** IPs regardless of who
queries it — it works here because the partner EC2 can now *route* to those IPs
via the TGW, not because of any DNS trick.

## 2. Case B — VPC Lattice (L7, no route tables)
Install the [AWS Gateway API Controller for VPC Lattice](https://github.com/aws/aws-application-networking-k8s)
in the `dev` cluster — same Gateway API pattern as the ALB in
`01-TEST-INGRESS-GATEWAY-API.md`, different `GatewayClass`:
```bash
kubectl create namespace aws-application-networking-system
kubectl apply -f https://raw.githubusercontent.com/aws/aws-application-networking-k8s/main/files/controller-installation/gatewayclass.yaml

# IAM — Pod Identity, same pattern as Karpenter/external-dns in this repo (Pod Identity over IRSA)
curl -s https://raw.githubusercontent.com/aws/aws-application-networking-k8s/main/files/controller-installation/recommended-inline-policy.json -o /tmp/lattice-policy.json
aws iam create-policy --policy-name VPCLatticeControllerIAMPolicy --policy-document file:///tmp/lattice-policy.json
POLICY_ARN=$(aws iam list-policies --query 'Policies[?PolicyName==`VPCLatticeControllerIAMPolicy`].Arn' --output text)
aws iam create-role --role-name VPCLatticeControllerIAMRole \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"pods.eks.amazonaws.com"},"Action":["sts:AssumeRole","sts:TagSession"]}]}'
aws iam attach-role-policy --role-name VPCLatticeControllerIAMRole --policy-arn "$POLICY_ARN"
ROLE_ARN=$(aws iam list-roles --query 'Roles[?RoleName==`VPCLatticeControllerIAMRole`].Arn' --output text)
CLUSTER_NAME=$(cd ../../../../envs/dev/00-infra/01-eks && tofu output -raw cluster_name)
aws eks create-pod-identity-association --cluster-name "$CLUSTER_NAME" --role-arn "$ROLE_ARN" \
  --namespace aws-application-networking-system --service-account gateway-api-controller

helm install gateway-api-controller \
  oci://public.ecr.aws/aws-application-networking-k8s/aws-gateway-controller-chart \
  --version v2.1.3 --namespace aws-application-networking-system --set=serviceAccount.create=true
```
Allow the VPC Lattice managed network to reach pods (same `cluster_security_group_id`
as Case A, different source — a managed prefix list, not a CIDR):
```bash
PREFIX_LIST_ID=$(aws ec2 describe-managed-prefix-lists \
  --query "PrefixLists[?PrefixListName=='com.amazonaws.ap-southeast-1.vpc-lattice'].PrefixListId" --output text)
aws ec2 authorize-security-group-ingress --group-id "$CLUSTER_SG" \
  --ip-permissions "PrefixListIds=[{PrefixListId=$PREFIX_LIST_ID}],IpProtocol=-1"
```
Expose `whoami` through the Gateway API, `gatewayClassName: amazon-vpc-lattice`:
```bash
kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: lattice-gw
spec:
  gatewayClassName: amazon-vpc-lattice
  listeners:
    - name: http
      port: 80
      protocol: HTTP
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: whoami
spec:
  parentRefs: [{ name: lattice-gw }]
  rules:
    - backendRefs: [{ name: whoami, port: 80 }]
EOF
```
Associate the **partner VPC** with the Lattice service network the controller
created (console: VPC Lattice → Service networks → Associate VPC; or CLI once you
have the service network ID from `aws vpc-lattice list-service-networks`):
```bash
SN_ID=$(aws vpc-lattice list-service-networks --query 'items[0].id' --output text)
aws vpc-lattice create-service-network-vpc-association --service-network-identifier "$SN_ID" --vpc-identifier "$PARTNER_VPC"
```
From the partner EC2 — **no route table entry, no TGW, no NAT** on either side:
```bash
SVC_DNS=$(aws vpc-lattice list-services --query "items[?name=='whoami'].dnsEntry.domainName" --output text)
curl "http://$SVC_DNS"
```

## 3. Comparison

| | Transit Gateway | VPC Lattice |
|---|---|---|
| Layer | L3/L4 — any protocol, full network reachability | L7 — HTTP/HTTPS/gRPC services only |
| Wiring | Attachments + route tables on **both** sides | Service network **association** — no routes |
| Exposure unit | A routable IP (NLB, pod IP) | A named **Service** (DNS name), via Gateway API |
| Blast radius | Whole subnet reachable (SG is the only gate) | Only the routes/services you explicitly export |
| Cost | `$0.05/h`/attachment + `$0.02/GB` | `$0.025/h`/service + `$0.025/GB` + requests |
| Fits this repo's theme | Same shape as the partner/exchange NAT pattern in `docs/NETWORKING.md` | Same shape as the ALB Gateway API — different `GatewayClass`, same Kubernetes API |

## 4. Cleanup — VPC Lattice
```bash
kubectl delete httproute whoami; kubectl delete gateway lattice-gw
aws vpc-lattice delete-service-network-vpc-association --service-network-vpc-association-identifier \
  "$(aws vpc-lattice list-service-network-vpc-associations --service-network-identifier "$SN_ID" --query 'items[0].id' --output text)"
helm uninstall gateway-api-controller -n aws-application-networking-system
aws iam detach-role-policy --role-name VPCLatticeControllerIAMRole --policy-arn "$POLICY_ARN"
aws iam delete-role --role-name VPCLatticeControllerIAMRole
aws iam delete-policy --policy-arn "$POLICY_ARN"
```

## 5. Cleanup — Transit Gateway + partner VPC
```bash
kubectl delete svc whoami-internal
aws ec2 delete-route --route-table-id "$DEV_APP_RT" --destination-cidr-block 10.99.0.0/24
for att in $(aws ec2 describe-transit-gateway-vpc-attachments --filters "Name=transit-gateway-id,Values=$TGW" \
  --query 'TransitGatewayVpcAttachments[].TransitGatewayAttachmentId' --output text); do
  aws ec2 delete-transit-gateway-vpc-attachment --transit-gateway-attachment-id "$att"
done
aws ec2 delete-transit-gateway --transit-gateway-id "$TGW"
aws ec2 terminate-instances --instance-ids "$INSTANCE"
# then delete partner subnet, IGW (detach first), route table, security group, VPC
```
