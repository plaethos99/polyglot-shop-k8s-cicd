# 🚀 AWS ECR + EKS Complete CI/CD Deployment Guide

This guide details the complete end-to-end automation to **build and push Docker images to AWS ECR**, **provision an Amazon EKS cluster**, and **deploy the Polyglot Retail Store application** using **GitHub Actions**.

---

## 📐 Architecture & CI/CD Flow

```mermaid
flowchart TD
    subgraph GitHub["GitHub Repository (Branch: feat/eks-ecr-cicd)"]
        GitPush["git push / PR / Manual Trigger"]
        Workflow[".github/workflows/eks-ecr-cicd.yml"]
        GitPush --> Workflow
    end

    subgraph CI["Job 1: Build & Push"]
        Buildx["Docker Buildx (5 Services)\n• catalog  • orders\n• cart     • checkout\n• ui"]
        Tagging["Tags:\n• :latest\n• :<git-sha>"]
        Buildx --> Tagging
    end

    subgraph AWS_ECR["AWS Elastic Container Registry (ECR)"]
        ECR_Repos[("ECR Repositories\n• catalog\n• orders\n• cart\n• checkout\n• ui")]
    end

    subgraph Provisioning["Job 2 (Optional): Cluster Provisioning"]
        EKS_Create["eksctl create cluster\n(or Terraform)"]
    end

    subgraph EKS["Job 3: Deploy to Amazon EKS"]
        EKS_Cluster["Amazon EKS Cluster (retail-store)\n• 2x Managed Worker Nodes (t3.large)"]
        KubeDeploy["scripts/deploy-eks.sh\n• StorageClass (EBS/local-path)\n• Databases & Queues\n• Microservices Deployment\n• LoadBalancer Service"]
        ELB["AWS Elastic Load Balancer (ELB)\nhttp://<elb-dns>:8080"]
    end

    Workflow --> CI
    Tagging --> ECR_Repos
    Workflow -.-> Provisioning
    Provisioning -.-> EKS_Cluster
    CI --> EKS
    ECR_Repos --> KubeDeploy
    KubeDeploy --> EKS_Cluster
    EKS_Cluster --> ELB
```

---

## 🔑 1. Setup GitHub Secrets

To allow GitHub Actions to interact with your AWS account, configure two GitHub Secrets:

1. Open your repository on GitHub: `https://github.com/plaethos99/polyglot-shop-k8s-cicd`
2. Navigate to: **Settings** > **Secrets and variables** > **Actions**
3. Click **New repository secret** and add:

| Secret Name | Description | Example |
| :--- | :--- | :--- |
| `AWS_ACCESS_KEY_ID` | AWS IAM Access Key | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | AWS IAM Secret Access Key | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |

*(Optional Variables under **Settings > Variables**)*:
- `AWS_REGION`: `eu-north-1` *(defaults to `eu-north-1` if not set)*
- `EKS_CLUSTER_NAME`: `retail-store` *(defaults to `retail-store` if not set)*

### Minimum IAM Permissions Required:
Your AWS IAM user or role needs permissions for:
- **ECR**: `ecr:*` (to create repositories, get authorization tokens, and push images)
- **EKS**: `eks:*` (to create, describe, and update clusters)
- **CloudFormation**: `cloudformation:*` (used by `eksctl`)
- **EC2 & VPC**: `ec2:*` (to create VPC, subnets, NAT gateways, and node security groups)
- **ELB**: `elasticloadbalancing:*` (to provision the LoadBalancer for the UI)
- **IAM**: `iam:CreateRole`, `iam:PassRole`, `iam:AttachRolePolicy` (for cluster & node roles)

---

## ☸️ 2. Cluster Creation (100% Automated by GitHub Actions)

**You do NOT need to install eksctl or create the cluster locally from your laptop.**

GitHub Actions handles the entire lifecycle automatically:
1. When the pipeline runs, **Job 2 (`create-or-verify-eks-cluster`)** checks if an EKS cluster named `retail-store` exists in your AWS region.
2. **If it doesn't exist**: GitHub Actions automatically launches `eksctl` and provisions the complete 2-node cluster (`t3.large`, gp3 storage, VPC, OIDC, managed node groups).
3. **If it already exists**: GitHub Actions simply confirms it is `ACTIVE` and immediately proceeds to deploy your application.

*(Optional)*: If you ever want to create or manage the cluster manually from your terminal, you can still use:
```bash
eksctl create cluster -f deployment-me/eks/eksctl-cluster.yaml
```

## 🚢 3. How the CI/CD Pipeline Operates

The workflow file is defined at:
**[`.github/workflows/eks-ecr-cicd.yml`](.github/workflows/eks-ecr-cicd.yml)**

### Triggers:
- **Automatic:** On push to `main` or `feat/eks-ecr-cicd` whenever code changes in `src/`, `deployment-me/k8s/`, or `scripts/`.
- **Manual (`workflow_dispatch`):** Can be triggered anytime from the GitHub Actions web interface with custom parameters (cluster name, region, custom image tag).

### Pipeline Stages:
1. **`build-and-push-ecr`**:
   - Uses a parallel build matrix for all 5 services (`catalog`, `orders`, `cart`, `checkout`, `ui`).
   - Configures AWS credentials and authenticates with Amazon ECR.
   - Automatically provisions any missing ECR repositories.
   - Builds images using Buildx and pushes two tags: `:latest` and `:<git-sha>`.
   - Uses GitHub Actions cache (`type=gha`) to ensure lightning-fast subsequent builds.

2. **`create-eks-cluster` (Optional)**:
   - Only triggers if `create_eks_cluster` is set to `true`.
   - Installs `eksctl` and provisions the cluster if it does not already exist.

3. **`deploy-to-eks`**:
   - Connects to the EKS cluster using `aws eks update-kubeconfig`.
   - Executes [`scripts/deploy-eks.sh`](scripts/deploy-eks.sh).
   - Generates the ECR pull secret and patches the default ServiceAccount.
   - Deploys database backends: RabbitMQ, PostgreSQL, Redis, MariaDB, DynamoDB-local.
   - Deploys the 5 microservices pointing to the exact ECR image tag from the current commit (`${{ github.sha }}`).
   - Sets the UI service to `type: LoadBalancer`.
   - Waits for the AWS Elastic Load Balancer (ELB) to allocate an external hostname.
   - Writes the live application URL directly to the **GitHub Actions Run Summary**!

---

## 🖥️ 4. Manual / Local Deployment to EKS

If you ever wish to deploy to EKS directly from your terminal:

```bash
chmod +x scripts/deploy-eks.sh

# Syntax: ./scripts/deploy-eks.sh <CLUSTER_NAME> <AWS_REGION> <AWS_ACCOUNT_ID> [IMAGE_TAG]
./scripts/deploy-eks.sh retail-store eu-north-1 517178430929 latest
```

---

## 🔍 5. Verification & Testing the Live Store

Once the pipeline completes:

1. **Check Pods on EKS**:
   ```bash
   aws eks update-kubeconfig --name retail-store --region eu-north-1
   kubectl -n retail-store get pods -o wide
   ```

2. **Check the External LoadBalancer Endpoint**:
   ```bash
   kubectl -n retail-store get svc ui
   ```
   *Output example:*
   ```text
   NAME   TYPE           CLUSTER-IP       EXTERNAL-IP                                                              PORT(S)          AGE
   ui     LoadBalancer   10.100.123.45   k8s-retailstore-ui-xxxxxx-123456789.eu-north-1.elb.amazonaws.com   8080:31234/TCP   3m
   ```

3. **Open in Browser**:
   ```text
   http://<EXTERNAL-IP>:8080
   ```

---

## 🧹 6. Teardown / Cost Saving Cleanup

When you are done testing, you can delete the cluster and all AWS resources directly from **GitHub Actions** with one click!

### Method A: One-Click Teardown via GitHub Actions (Recommended)
1. In your GitHub repository, click the **Actions** tab.
2. In the left sidebar, select **Destroy EKS Cluster & Teardown Resources**.
3. Click the **Run workflow** button on the right.
4. In the inputs modal:
   - **EKS Cluster Name:** `retail-store`
   - **AWS Region:** `eu-north-1`
   - **Delete ECR images:** Check if you want to purge ECR container images too.
   - **Confirmation:** Type `destroy`
5. Click **Run workflow**.

> 🛡️ **What this does safely:**
> - First deletes the Kubernetes LoadBalancer services so AWS ELBs are cleanly de-provisioned.
> - Deletes the `retail-store` namespace.
> - Invokes `eksctl delete cluster` to tear down the EC2 worker instances, VPC, subnets, and CloudFormation stacks.
> - Stops all further AWS billing immediately.

---

### Method B: Manual CLI Teardown
If you ever want to destroy it from a terminal instead:
```bash
chmod +x scripts/destroy-eks.sh
./scripts/destroy-eks.sh retail-store eu-north-1
```
