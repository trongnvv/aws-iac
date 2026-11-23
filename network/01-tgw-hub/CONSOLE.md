# Lab 1 — TGW hub + segmentation: console walkthrough

Same lab as the Terraform in this folder, done by hand — useful for exam-style click-through
practice, or to see exactly what each resource is for before reading the `.tf` files. Region:
`ap-southeast-1`. Covers **Core** only (3 VPCs + TGW hub + segmentation); the optional `5-egress`
and `6-region2-peering` stretch layers aren't in this walkthrough yet.

## 1. Three VPCs
**VPC console → Your VPCs → Create VPC** (VPC only, not "VPC and more") — repeat 3×:

| Name | CIDR |
|---|---|
| `net-lab-shared` | `10.0.0.0/16` |
| `net-lab-prod` | `10.1.0.0/16` |
| `net-lab-dev` | `10.2.0.0/16` |

## 2. One subnet per VPC (+ one extra for shared)
**VPC console → Subnets → Create subnet**, one at a time:

| VPC | Name | CIDR | AZ |
|---|---|---|---|
| `net-lab-shared` | `net-lab-shared-public` | `10.0.0.0/24` | pick AZ **a** — use the same AZ for every subnet below |
| `net-lab-prod` | `net-lab-prod-public` | `10.1.0.0/24` | AZ a |
| `net-lab-dev` | `net-lab-dev-public` | `10.2.0.0/24` | AZ a |
| `net-lab-shared` | `net-lab-shared-tgw` | `10.0.255.0/24` | AZ a |

The 4th one (`-tgw`) is the **shared VPC's dedicated TGW-attachment subnet** — keeps the shared
VPC's own public subnet free for a future NAT (see `5-egress`, not covered here) without the TGW
attachment competing for it.

For the three `-public` subnets: **Subnet → Edit subnet settings → enable Auto-assign public IPv4**.

## 3. Internet Gateways
**VPC console → Internet gateways → Create internet gateway**, one per VPC (`net-lab-shared`,
`net-lab-prod`, `net-lab-dev`) → **Actions → Attach to VPC** → pick the matching VPC.

## 4. Route tables (one per VPC, for the `-public` subnet)
**VPC console → Route tables → Create route table**, one per VPC, associate with that VPC's
`-public` subnet (**Route tables → Subnet associations → Edit subnet associations**):

- Add route `0.0.0.0/0 → Internet Gateway` (pick that VPC's IGW) — this is what Session Manager
  needs to reach AWS's SSM endpoints.
- **Leave the `10.0.0.0/8 → TGW` route out for now** — you can't create it until the TGW exists
  (step 7). Come back and add it after step 11.

The `-tgw` subnet (shared VPC) needs its own separate route table too (empty for now, no 0/0 —
it's not going to be a public-facing subnet). Create it, associate it to `net-lab-shared-tgw`.

## 5. Security groups
**VPC console → Security groups → Create security group**, one per VPC, named `net-lab-<name>`:
- Inbound: **ICMP, All**, source `10.0.0.0/8` (ping from any lab VPC)
- Outbound: leave the default **All traffic, 0.0.0.0/0**

## 6. Transit Gateway
**VPC console → Transit Gateways → Create transit gateway**
- Name: `net-lab`
- **Uncheck** "Default route table association" and "Default route table propagation" — this lab
  segments traffic by hand with two custom route tables, not the default one.
- Everything else default. Creation takes a minute or two.

## 7. TGW attachments (3×)
**VPC console → Transit Gateway attachments → Create transit gateway attachment**, once per VPC:

| Name | VPC | Subnet |
|---|---|---|
| `net-lab-shared` | `net-lab-shared` | `net-lab-shared-tgw` |
| `net-lab-prod` | `net-lab-prod` | `net-lab-prod-public` |
| `net-lab-dev` | `net-lab-dev` | `net-lab-dev-public` |

Attachment type: **VPC**. Leave DNS support on.

## 8. Two TGW route tables
**VPC console → Transit Gateway route tables → Create transit gateway route table**:
- `net-lab-shared` (the "shared" route table — shared VPC's attachment lives here)
- `net-lab-spoke` (prod + dev attachments live here)

### Associate
**Transit Gateway route tables → [table] → Associations tab → Create association**:
- `net-lab-shared` table ← associate the **shared** attachment
- `net-lab-spoke` table ← associate the **prod** attachment, then again for the **dev** attachment

### Propagate (this is the segmentation)
**Transit Gateway route tables → [table] → Propagations tab → Create propagation**:
- `net-lab-shared` table ← propagate **prod** attachment, then **dev** attachment (shared VPC
  learns routes to both spokes)
- `net-lab-spoke` table ← propagate **shared** attachment (both spokes learn the route to shared)

**Do NOT propagate prod into the spoke table, or dev into the spoke table** — that's the whole
point: the spoke table only ever learns "shared," never its sibling spoke. This is what makes
prod ⊥ dev.

## 9. Back to the VPC route tables — add the TGW route
Now that the TGW exists, go back to each of the 3 `-public` route tables from step 4 (shared,
prod, dev) and add:
- `10.0.0.0/8 → Transit Gateway` (pick `net-lab`)

## 10. SSM access for the test instances (no SSH, no bastion)
**IAM console → Roles → Create role**
- Trusted entity: **AWS service → EC2**
- Permissions: attach **AmazonSSMManagedInstanceCore**
- Name: `net-lab-ssm`

This auto-creates an instance profile of the same name — EC2 picks it up by role name when you
launch.

## 11. Test EC2 in each VPC
**EC2 console → Launch instance**, once per VPC (shared/prod/dev):
- AMI: **Amazon Linux 2023**, architecture **arm64** (matches `t4g.micro`)
- Instance type: `t4g.micro`
- Network: that VPC's `-public` subnet (shared uses `-public`, not `-tgw` — the test host doesn't
  live in the TGW-attachment subnet)
- **Key pair: None** — SSM only, no SSH
- IAM instance profile: `net-lab-ssm`
- Security group: that VPC's security group from step 5
- Name: `net-lab-<vpc>`

## 12. Verify
**EC2 console → select the shared instance → Connect → Session Manager → Connect** (no SSH key
needed). From inside:
```bash
ping <prod private IP>   # OK — shared can reach both spokes
ping <dev private IP>    # OK
```
Now **Connect** to the **prod** instance instead:
```bash
ping <dev private IP>    # times out — prod ⊥ dev, exactly as designed
```

Find private IPs under **EC2 → Instances → [instance] → Private IPv4 address**.

## Clean up
Delete in this order (reverse of creation) or the VPC deletions will fail with dependency errors:
EC2 instances → TGW attachments (wait for them to detach) → Transit Gateway → TGW route tables →
VPC route table entries referencing the TGW → Internet Gateways (detach first) → subnets → VPCs →
the `net-lab-ssm` IAM role.
