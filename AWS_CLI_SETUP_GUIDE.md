# 🛠️ AWS CLI v2 Installation & Configuration Guide (Linux / Ubuntu)

This guide provides detailed, step-by-step instructions for installing and configuring the **AWS Command Line Interface version 2 (AWS CLI v2)** on Linux distributions (Ubuntu/Debian, EC2 instances, or local Linux machines).

The AWS CLI is essential in this repository for authenticating to **Amazon ECR**, pushing container images, managing **Amazon EKS**, and interacting with AWS cloud resources.

---

## 📋 Prerequisites

- **Operating System**: Linux x86_64 (e.g., Ubuntu 20.04/22.04/24.04 LTS or Debian)
- **User Privileges**: `sudo` / root permissions
- **AWS Credentials**: An AWS IAM user or role with appropriate permissions (e.g., `AmazonEC2ContainerRegistryPowerUser` or administrator access)

---

## 🚀 Step 1: Install Required Dependencies

Ensure package indices are up to date and install `curl` (to download the installer package) and `unzip` (to extract the zip archive).

```bash
sudo apt-get update && sudo apt-get install -y unzip curl
```

> **Why this is needed**:
> - `curl`: Securely fetches the official zip package from Amazon S3/CloudFront.
> - `unzip`: Decompresses the installation archive.

---

## 📥 Step 2: Download the Official AWS CLI v2 Bundle

Download the official AWS CLI v2 distribution package for Linux x86_64:

```bash
curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip'
```

> **Note**: For ARM64 architectures (e.g., AWS Graviton instances), replace the URL with `https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip`.

---

## 📂 Step 3: Unpack the Installation Files

Extract the contents of the downloaded `awscliv2.zip` archive:

```bash
unzip awscliv2.zip
```

This unpacks the installer files into a directory named `./aws` in your current working directory.

---

## ⚙️ Step 4: Run the Installer

Execute the install script with administrative privileges:

```bash
sudo ./aws/install
```

### Upgrading an Existing Installation
If you already have AWS CLI installed and want to update it to the latest version, run:
```bash
sudo ./aws/install --update
```

Default installation targets:
- Executables: `/usr/local/bin/aws`
- Installation files: `/usr/local/aws-cli`

---

## 🔍 Step 5: Verify the Installation

Verify that the AWS CLI is properly installed and accessible in your system `PATH`:

```bash
aws --version
```

**Expected output (example)**:
```text
aws-cli/2.24.x Python/3.12.x Linux/6.8.0-xx-generic exe/x86_64.ubuntu.24
```

---

## 🔐 Step 6: Configure AWS Credentials and Settings

Configure your AWS credentials, default region, and output format using the `aws configure set` command:

```bash
aws configure set aws_access_key_id YOURKEY
aws configure set aws_secret_access_key YOUR_ACCESS_KEY
aws configure set region REGION
aws configure set output json
```

### Parameter Explanations

| Parameter | Description | Example |
| :--- | :--- | :--- |
| `aws_access_key_id` | Your AWS IAM Access Key ID | `AKIAIOSFODNN7EXAMPLE` |
| `aws_secret_access_key` | Your AWS IAM Secret Access Key | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `region` | Default AWS region where resources reside | `us-east-1`, `eu-west-1`, `ap-south-1` |
| `output` | Default format for command responses | `json` (recommended), `yaml`, `text`, `table` |

---

### Alternative: Interactive Configuration Prompt
You can also run the interactive wizard:
```bash
aws configure
```
You will be prompted interactively:
```text
AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
Default region name [None]: us-east-1
Default output format [None]: json
```

---

### Where Configuration Files Are Stored
The CLI stores these settings in your user home directory:
- **`~/.aws/credentials`**: Stores the access key and secret key securely:
  ```ini
  [default]
  aws_access_key_id = AKIAIOSFODNN7EXAMPLE
  aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
  ```
- **`~/.aws/config`**: Stores the default region and output format:
  ```ini
  [default]
  region = us-east-1
  output = json
  ```

---

## ✅ Step 7: Verify Authentication and AWS Connectivity

Test that your credentials are valid and can reach the AWS API by querying your caller identity:

```bash
aws sts get-caller-identity
```

**Expected JSON response**:
```json
{
    "UserId": "AIDASAMPLEUSERIDEXAMPLE",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/your-username"
}
```

### Verify ECR Access (Repository Workflow)
To test logging in to your Amazon ECR registry:
```bash
aws ecr get-login-password --region <your-region> | docker login --username AWS --password-stdin <your-account-id>.dkr.ecr.<your-region>.amazonaws.com
```

---

## 🧹 Step 8: Clean Up Installer Files (Optional)

Once the installation is complete and verified, remove the downloaded archive and extracted folder to save disk space:

```bash
rm -rf awscliv2.zip ./aws
```

---

## 🔒 Security Best Practices

1. **Never Commit Credentials**: Never hardcode or commit `~/.aws/credentials` or access keys into Git repositories.
2. **Use EC2 IAM Roles**: If running on an AWS EC2 instance (e.g., your build machine or Kubernetes master node), attach an **IAM Role** to the instance instead of managing static access keys. The AWS CLI will automatically retrieve temporary credentials via the EC2 Instance Metadata Service (IMDS).
3. **Principle of Least Privilege**: Ensure your IAM user or role only has permissions to resources it needs (e.g., specific ECR repositories or EKS clusters).
4. **Rotate Keys Regularly**: If using static IAM access keys, rotate them periodically and delete unused access keys.

---

## ❓ Troubleshooting

| Issue | Cause | Solution |
| :--- | :--- | :--- |
| `aws: command not found` | `/usr/local/bin` not in `$PATH` | Add `export PATH=$PATH:/usr/local/bin` to `~/.bashrc` and run `source ~/.bashrc`. |
| `The security token included in the request is invalid` | Misconfigured Access Key ID or Secret Key | Re-check credentials and run `aws configure set` again. |
| `SignatureDoesNotMatch` | Special characters or typo in Secret Key | Re-copy and set `aws_secret_access_key`. |
| `RequestTimeTooSkewed` | System clock is out of sync | Resync system clock: `sudo timedatectl set-ntp true`. |
| `Permission denied` when running `./aws/install` | Missing root privileges | Prepend `sudo`: `sudo ./aws/install`. |
