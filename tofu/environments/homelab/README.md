# Homelab Environment

This directory contains the root OpenTofu configuration for the `homelab` environment.

## State backend bootstrap

State is stored in an S3-compatible MinIO backend on the workstation, reached over Tailscale (MagicDNS name `omarchy.tail12d19f.ts.net`). OpenTofu requires the bucket to exist before it can initialize, so the backend is bootstrapped manually.

### Prerequisites

1. Log into the MinIO Console.
2. Create a bucket named `tofu-state-homelab`.
3. Enable versioning on the bucket, so a corrupted or accidentally overwritten state file can be rolled back.
4. Create an access key and secret key restricted to this bucket.

### Initialization

Export the MinIO credentials as standard AWS environment variables so the `s3` backend can authenticate, then init from this directory:

```bash
export AWS_ACCESS_KEY_ID="minio_access_key"
export AWS_SECRET_ACCESS_KEY="minio_secret_key"

cd tofu/environments/homelab
tofu init
```

## Trade-offs

**State locking is disabled.** The `s3` backend expects DynamoDB for locking, which MinIO does not provide. In a solo homelab there is no realistic risk of concurrent `tofu apply` runs.

**The workstation must be up to run OpenTofu.** The state lives on a machine that is not always on. Any `tofu` command needs the workstation online and reachable over Tailscale — including during disaster recovery, where bringing the workstation and MinIO up is a prerequisite to rebuilding the cluster from code.
