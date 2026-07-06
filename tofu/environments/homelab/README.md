# Homelab Environment

This directory contains the root OpenTofu configuration for the 'homelab' environment.

## State Backend Bootstrap

The state is stored in an S3-compatible MinIO backend on the workstation. Because the OpenTofu requires the bucket to exist before it can initialize, the backend must be bootstrapped manually.

### Prerequisites
1. Log into the MinIO Console
2. Create a bucket named 'tofu-state-homelab'
3. Create an Access Key and Secret Key restricted to this bucket.

### Initialization
Before running OpenTofu commands, export the MinIO credentials as standard AWS env variables so the 'S3' backend can authenticate:

'''bash
export AWS_ACCESS_KEY_ID="minio_access_key"
export AWS_SECRET_ACCESS_KEY="minio_secret_key"

Once exported, init the env:

tofu init

### Step 4: Init OpenTofu
Once you have created the bucket in MinIO and exported your credentials in your terminal, rn the init comman from within the 'tofu/environment/homelab' directory:

'''bash
cd tofu/environment/homelab
tofu init

### State Locking Trade-off
The 's3' OpenTofu backend natively requires AWS DynamoDB for state locking. Because we are using MinIO, state locking is currently disabled (it only mimics S3). In a solo homelab env, the risk of concurrent 'tofu apply' executions, especially in a CICD environment is impossible.
