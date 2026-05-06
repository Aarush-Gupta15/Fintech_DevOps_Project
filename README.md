# Fintech DevOps Project

A simple fintech user management application built with **Node.js + Express** backend, **HTML/JS** frontend, and **PostgreSQL** database — containerized with Docker and deployed using Kubernetes on AWS with CI/CD pipeline.

> **College Project** — B.Tech CSE 3rd Year | CSET 452 DevOps

---

## Tech Stack

| Component          | Technology                          |
|--------------------|-------------------------------------|
| Backend            | Node.js, Express.js                 |
| Frontend           | HTML, CSS, JavaScript (Nginx)       |
| Database           | PostgreSQL 15                       |
| Containerization   | Docker, Docker Compose              |
| IaC                | Terraform                           |
| Orchestration      | Kubernetes (AWS EKS)                |
| CI/CD              | GitHub Actions + Argo CD            |
| Cloud              | AWS (EKS, RDS, VPC, Route53)       |

---

## Project Structure

```
fintech-devops/
├── server.js                    # Express backend API
├── index.html                   # Frontend UI
├── package.json                 # Node dependencies
├── Dockerfile                   # Backend Docker image
├── frontend.Dockerfile          # Frontend Docker image (nginx)
├── docker-compose.yml           # Local dev setup
├── init.sql                     # Database initialization
│
├── terraform/                   # Infrastructure as Code
│   ├── modules/
│   │   ├── vpc/main.tf          # VPC, subnets, NAT, IGW
│   │   ├── eks/main.tf          # EKS cluster + node groups
│   │   └── rds/main.tf          # PostgreSQL RDS
│   └── environments/
│       ├── dev/main.tf          # Dev config
│       └── prod/main.tf         # Prod (multi-region)
│
├── k8s/                         # Kubernetes manifests
│   ├── namespace.yaml
│   ├── configmap.yaml
│   ├── secret.yaml
│   ├── postgres-deployment.yaml
│   ├── backend-deployment.yaml
│   ├── frontend-deployment.yaml
│   ├── hpa.yaml                 # Auto-scaling
│   ├── network-policy.yaml      # Security between services
│   └── argocd/
│       └── application.yaml     # Argo CD config
│
├── .github/workflows/
│   └── ci-cd.yml                # CI/CD pipeline
│
└── monitoring/                  # For future use
```

---

## How to Run Locally

```bash
git clone https://github.com/aarushgupta/fintech-devops.git
cd fintech-devops
docker-compose up --build

# Frontend: http://localhost:8080
# Backend: http://localhost:3000/api/health
```

---

## API Endpoints

| Method | Endpoint       | Description               |
|--------|---------------|---------------------------|
| GET    | /api/health   | Liveness check            |
| GET    | /api/ready    | Readiness check (DB test) |
| GET    | /api/metrics  | Basic app metrics         |
| GET    | /api/users    | Get all users             |
| POST   | /api/users    | Add a new user            |

---

## Author

**Aarush Gupta** — B.Tech CSE 3rd Year

---
---

# CSET 452 — DevOps Class Assignment Answers

---

## (a) Architecture Design (4 Marks)

### VPC Structure

I designed the VPC with CIDR `10.0.0.0/16` and spread it across 2 Availability Zones (AZs) for high availability. The structure is:

- **Public Subnets** (1 per AZ) — These hold the Application Load Balancer (ALB) which is the entry point for users. They have an Internet Gateway so they can receive traffic from outside.
- **Private Subnets** (1 per AZ) — These hold our EKS worker nodes, RDS database, and Redis cache. They are not directly accessible from the internet which makes them secure. A NAT Gateway lets them make outbound calls (like pulling Docker images) without being exposed.

I chose 2 AZs because AWS EKS requires minimum 2, and it gives us redundancy — if one AZ fails, the other keeps running.

### Placement of Services

| Service        | Where         | Why                                                    |
|----------------|---------------|--------------------------------------------------------|
| ALB (Ingress)  | Public subnet | It needs to receive traffic from users on the internet |
| EKS Nodes      | Private subnet| Pods should not be exposed directly, ALB routes to them|
| RDS PostgreSQL | Private subnet| Database should never be reachable from internet       |
| Redis Cache    | Private subnet| Only backend needs to access it, so keep it internal   |

### Load Balancing

I'm using AWS ALB (Application Load Balancer) as the Kubernetes Ingress:
- ALB handles SSL/TLS termination
- Routes `/api/*` requests to backend service and `/*` to frontend
- It does health checks on pods using the readiness probes we configured

I chose ALB over NLB because ALB supports HTTP path-based routing which we need for our microservice setup. NLB is for TCP-level stuff which is more complex for our use case.

### Multi-Region Design

For multi-region, I'm going with an **Active-Passive** setup:

```
            Route53 (DNS Failover)
                    |
         ┌─────────┴─────────┐
         ▼                    ▼
   ap-south-1            ap-southeast-1
   (PRIMARY)             (SECONDARY/DR)
   Full traffic          Standby mode
   VPC + EKS + RDS       VPC + EKS + RDS replica
```

- Primary region (Mumbai) handles all the traffic normally
- Secondary region (Singapore) stays on standby with minimal resources running
- Route53 does health checks on primary every 10 seconds
- If primary goes down, Route53 switches DNS to secondary automatically

I chose Active-Passive instead of Active-Active because:
- Active-Active needs both regions to handle writes simultaneously, which creates data conflict issues
- Active-Passive is simpler to implement and costs about 40% less
- For a startup, ~90 seconds of failover time is acceptable

### Security Considerations

- Everything important (EKS, RDS) sits in private subnets
- Security Groups restrict which services can talk to each other
- Network Policies inside K8s add another layer of access control
- Secrets go in AWS Secrets Manager, never hardcoded
- All data encrypted at rest (RDS, EBS) and in transit (TLS via ALB)

### Cost Trade-offs

| Choice                    | Saves Money Because                              |
|---------------------------|--------------------------------------------------|
| t3.medium for dev         | Burstable instances are cheap (~$30/month)       |
| Single NAT Gateway in dev | One NAT vs 2 saves ~$35/month                   |
| Multi-AZ RDS only in prod | No need to pay double for DB in development      |
| Active-Passive DR         | Secondary region runs minimal resources          |

---

## (b) Terraform Strategy (4 Marks)

### Module Design

I split the Terraform code into 3 reusable modules:

1. **VPC Module** (`modules/vpc/`) — Creates the VPC, public/private subnets, Internet Gateway, NAT Gateway, and route tables
2. **EKS Module** (`modules/eks/`) �� Creates the EKS cluster, IAM roles, and managed node groups
3. **RDS Module** (`modules/rds/`) — Creates the PostgreSQL database, subnet group, and security group

The reason for modules is reusability. The same VPC module can be called for both primary and secondary region — just pass different variables. This avoids copy-pasting code.

### Remote State Management

```hcl
backend "s3" {
  bucket         = "fintech-terraform-state"
  key            = "dev/terraform.tfstate"
  region         = "ap-south-1"
  dynamodb_table = "terraform-locks"
  encrypt        = true
}
```

I store state in S3 because:
- Multiple team members can access the same state
- S3 has versioning so we can recover if state gets corrupted
- DynamoDB table provides locking — prevents two people from running `terraform apply` at the same time and messing things up

### Environment Separation

I'm using **folder-based separation**:

```
environments/
├── dev/main.tf       → state: s3://fintech-terraform-state/dev/terraform.tfstate
└── prod/main.tf      → state: s3://fintech-terraform-state/prod/terraform.tfstate
```

I chose folders over Terraform workspaces because:
- With folders, each environment has its own config file, so it's harder to accidentally apply prod changes
- Different environments can use different instance sizes, module versions etc.
- Code review is easier — a PR only touches the specific environment folder

### Multi-Region Handling

For multi-region, I use Terraform **provider aliases**:

```hcl
provider "aws" {
  region = "ap-south-1"
  alias  = "primary"
}

provider "aws" {
  region = "ap-southeast-1"
  alias  = "secondary"
}

module "vpc_primary" {
  source    = "../../modules/vpc"
  providers = { aws = aws.primary }
}

module "vpc_secondary" {
  source    = "../../modules/vpc"
  providers = { aws = aws.secondary }
}
```

This way, same module creates infrastructure in both regions with just different provider.

### Dependency Handling

Terraform figures out dependencies automatically through references. For example:
- EKS module uses `module.vpc.private_subnet_ids` — so Terraform knows VPC must be created first
- RDS module uses `module.vpc.vpc_id` — same thing, VPC comes before RDS

The order becomes: VPC �� EKS + RDS (parallel since both depend on VPC only)

### Challenges

| Problem         | How I'd Handle It                                         |
|-----------------|-----------------------------------------------------------|
| State Drift     | Run `terraform plan` in CI daily to detect manual changes |
| Region Sync     | Use same modules for both regions so configs stay same    |
| Secrets in State| Mark variables as `sensitive = true`, encrypt S3 bucket   |
| Slow Apply      | Use `-target` flag to only apply specific modules         |

---

## (c) Docker & Image Strategy (3 Marks)

### Dockerfile Optimization

I use **multi-stage builds** to keep production images small:

```dockerfile
# Stage 1: Install dependencies (this stage is thrown away)
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

# Stage 2: Final image (only has what's needed to run)
FROM node:18-alpine AS production
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY server.js .
USER appuser
CMD ["node", "server.js"]
```

What makes it optimized:
- **Multi-stage**: Builder stage has build tools but final image doesn't carry that weight
- **Alpine base**: `node:18-alpine` is ~120MB vs regular `node:18` which is ~900MB
- **`npm ci`**: Installs exactly from lockfile (faster + deterministic)
- **Only production deps**: `--only=production` skips test/dev packages
- **Layer ordering**: package.json copied first so Docker caches the dependency layer (doesn't re-download unless package.json changes)

### Reducing Size and Vulnerabilities

| What I Did               | Why                                              |
|--------------------------|--------------------------------------------------|
| Alpine base images       | Much smaller (120MB vs 900MB)                    |
| Non-root user (`USER appuser`) | If container is compromised, attacker can't get root |
| Only production deps     | Less code = less attack surface                  |
| Trivy scan in CI         | Catches known CVEs before deployment             |
| No unnecessary tools     | No curl/wget in prod image = fewer exploit paths |

### CI/CD Integration

The flow is:
1. Developer pushes code
2. GitHub Actions runs tests
3. If tests pass → Docker build (multi-stage)
4. Trivy scans the built image for vulnerabilities
5. If no critical vulns → push to Docker Hub with commit SHA as tag
6. Update K8s manifest with new tag → Argo CD deploys it

**Image tagging strategy**: I tag images with the first 7 characters of the git commit SHA (e.g., `fintech-backend:a3f7b2c`). This way:
- Every image maps to exact source code
- Easy to roll back (just redeploy the older SHA)
- `latest` tag is also pushed for convenience but SHA is used for actual deployments

---

## (d) Kubernetes Deployment (4 Marks)

### Zero-Downtime Releases

I configured the deployment with Rolling Updates:

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1          # Start 1 new pod before killing old
    maxUnavailable: 0    # Don't kill old pod until new one is ready
```

How this gives zero downtime:
1. K8s creates a new pod with the updated image
2. The new pod starts up and K8s checks its readiness probe (`/api/ready`)
3. Readiness probe checks if the app can connect to the database
4. Only after the probe passes, K8s sends traffic to the new pod
5. Then it terminates the old pod
6. If the new pod keeps failing readiness, old pods keep serving — nothing breaks

The key probes:
- **Liveness probe** (`/api/health`) — restarts pod if app is stuck/frozen
- **Readiness probe** (`/api/ready`) — only sends traffic when DB connection works

### Autoscaling

I'm using **HPA (Horizontal Pod Autoscaler)**:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  minReplicas: 2
  maxReplicas: 8
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          averageUtilization: 70
```

This means:
- Always have at least 2 pods running (for availability)
- If average CPU goes above 70%, add more pods (up to 8)
- If CPU drops, slowly remove extra pods

I chose HPA over VPA because:
- HPA adds more pods (horizontal scaling) — works great for stateless services like our backend
- VPA makes existing pods bigger (vertical scaling) — requires restarting the pod which causes brief downtime
- HPA is simpler and more commonly used in production

### Secrets Management

Right now I'm using Kubernetes Secrets:
```yaml
apiVersion: v1
kind: Secret
type: Opaque
data:
  DB_PASSWORD: cG9zdGdyZXM=   # base64 encoded
```

This is basic and works for learning, but in real production I'd use **AWS Secrets Manager** with the External Secrets Operator because:
- K8s secrets are just base64 (not real encryption)
- AWS Secrets Manager provides encryption, access control, and audit logs
- Secrets can be auto-rotated without redeploying

### Inter-Service Communication

Services talk to each other through **ClusterIP Services** and Kubernetes DNS:
- Frontend → `backend-service:3000` → Backend pods
- Backend → `postgres-service:5432` → PostgreSQL pod

I also added **Network Policies** to restrict who can talk to whom:
- Only backend pods can connect to PostgreSQL on port 5432
- Only frontend pods can connect to backend on port 3000
- This prevents lateral movement if one service gets compromised

### GitOps with Argo CD

Argo CD watches our Git repository and keeps the cluster in sync:

```yaml
syncPolicy:
  automated:
    prune: true       # Deletes stuff removed from Git
    selfHeal: true    # Reverts any manual kubectl changes
```

The flow:
1. CI pipeline updates image tag in K8s manifests and pushes to Git
2. Argo CD detects the change (polls every 3 minutes)
3. Argo CD applies the new manifests to the cluster
4. If someone manually does `kubectl edit`, Argo CD reverts it (self-heal)

For rollback, we just do `git revert` and Argo CD automatically syncs back to the previous state.

---

## (e) CI/CD Pipeline Design (3 Marks)

### Pipeline Stages

```
┌────────┐    ┌───────��──────┐    ┌──────────┐    ┌──────────┐
│  TEST  │ →  │ BUILD & PUSH │ →  │  DEPLOY  │ →  �� ROLLBACK │
│        │    │              │    │ (GitOps) │    │(if fails)│
└─────��──┘    └──────────────┘    └──────────┘    └──────────┘
```

**Stage 1 — Test:**
- Checkout code from GitHub
- Install dependencies with `npm ci`
- Run any lint/test scripts
- Start the server and hit `/api/health` to verify it works

**Stage 2 — Build & Push:**
- Build Docker images using our optimized multi-stage Dockerfiles
- Tag them with commit SHA (e.g., `fintech-backend:a3f7b2c`)
- Push to Docker Hub
- Run Trivy vulnerability scan on the images

**Stage 3 — Deploy:**
- Use `sed` to update the image tag in K8s manifest files
- Commit the updated manifests and push to main branch
- Argo CD picks up the change and deploys to the cluster automatically

**Stage 4 — Rollback (only if deploy fails):**
- If the deploy job fails, run `git revert HEAD`
- Push the reverted commit → Argo CD syncs back to the working state

### Trigger Mechanisms

| Event               | What Happens                              |
|---------------------|-------------------------------------------|
| Push to `main`      | Full pipeline runs (test → build → deploy)|
| Pull Request        | Only tests run (to validate before merge) |
| Deploy failure      | Rollback job auto-triggers                |

### Failure Handling

| What Goes Wrong        | What Happens                                          |
|------------------------|-------------------------------------------------------|
| Tests fail             | Pipeline stops immediately, no image gets built       |
| Docker build fails     | No push to registry, team gets notified               |
| Trivy finds critical vuln | Build fails, image is not deployed                 |
| Deploy fails           | Rollback job does `git revert`, Argo CD syncs old state|
| New pod crashes        | Readiness probe fails → old pods keep serving traffic |
| Argo CD sync fails     | Retries 3 times with backoff (5s, 10s, 20s)          |

---

## (f) Failure & Failover Scenario (2 Marks)

### Scenario: Primary AWS region goes down, need to route traffic to secondary region

### How Traffic Failover Works

I'm using **Route53 Failover Routing**:

1. Route53 has health checks that ping our primary ALB every 10 seconds
2. If the health check fails 3 times in a row (~30 seconds), it marks primary as unhealthy
3. Route53 automatically starts resolving our domain to the secondary region's ALB
4. DNS TTL is set to 60 seconds, so within ~90 seconds clients are connecting to DR region
5. The secondary region's EKS cluster scales up its pods using HPA to handle the incoming traffic

I considered AWS Global Accelerator for faster failover but Route53 is much cheaper and 90 seconds is acceptable for our startup use case.

### How Data Consistency is Handled

This is the tricky part. Here's my approach:

- **RDS Cross-Region Read Replica**: The primary database replicates asynchronously to a read replica in the secondary region. There's a few seconds of lag.
- **On failover**: The read replica gets promoted to a standalone primary database (takes ~1-2 minutes)
- **Trade-off**: We might lose the last 5 seconds of transactions that hadn't replicated yet. This is called RPO (Recovery Point Objective) = ~5 seconds.

For handling this in the application:
- Payment transactions use idempotency keys, so if the same transaction gets replayed after failover, it won't duplicate
- After the primary region comes back, we compare logs and reconcile any mismatches manually

### Tools/Services I Would Use

| Tool                    | What It Does                                    |
|-------------------------|-------------------------------------------------|
| AWS Route53             | DNS failover with health checks                 |
| RDS Cross-Region Replica| Keeps a copy of DB in the secondary region      |
| AWS CloudWatch          | Monitors health and triggers alarms             |
| EKS (both regions)      | Runs our app in both regions                    |
| Argo CD (both clusters) | Keeps both clusters deployed with same config   |
| AWS SNS                 | Sends alert to our team when failover happens   |

### Timeline of a Failover

```
T+0s     → Primary region stops responding
T+30s    → Route53 declares primary unhealthy (3 failed checks)
T+90s    → DNS points to secondary (60s TTL expires)
T+90s    → Secondary pods start getting traffic, HPA scales up
T+120s   → RDS replica promoted to primary
T+150s   → Everything fully working in secondary region
```

**Total recovery time: about 2-3 minutes**
**Data loss: up to ~5 seconds of recent transactions**

For a fintech startup this is reasonable. If we needed faster (sub-second), we'd need Global Accelerator + Aurora Global Database but that costs 3x more.

---

*End of Assignment Answers*
