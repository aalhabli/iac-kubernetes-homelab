# Homelab Environment

This directory contains the root OpenTofu configuration for the `homelab` environment.

## State backend bootstrap

State is stored in an S3-compatible MinIO backend on the workstation. OpenTofu requires the bucket to exist before it can initialize, so the backend is bootstrapped manually.

The endpoint is `http://minio.lab.alhabli.com:9000`, reached over the LAN ([ADR-0011](../../../docs/decisions/adr-0011-flat-l2-network.md)). It was previously the Tailscale MagicDNS name `omarchy.tail12d19f.ts.net`, which stopped resolving once the workstation moved onto the same L2 segment and the Tailnet was scoped back to off-network access.

The name is deliberately a **service** name rather than a host name. Longhorn, PBS, and Velero all target the same S3 endpoint, so MinIO can move to another host by changing one DNS record instead of every consumer.

### Name resolution prerequisites

`minio.lab.alhabli.com` is served by a **PiHole local DNS record** and resolves only inside the LAN. It is never published to Cloudflare. Two things must exist for it to work:

| What | Where | Value |
|---|---|---|
| Static address | Workstation (NetworkManager) | `192.168.1.10/24`, gw `192.168.1.1` |
| Local DNS record | PiHole | `minio.lab.alhabli.com` → `192.168.1.10` |

The workstation otherwise holds an ordinary DHCP lease (`192.168.1.56`) from the **ISP fiber box**, which serves the pool `192.168.1.50`–`192.168.1.199` for the wired segment. A static address **below** that pool is used instead of a DHCP reservation, matching how PiHole (`.3`), PBS (`.4`), and the Proxmox host (`.200`) are already addressed, and avoiding any dependency on reservation support in the fiber box firmware.

Set it on the workstation with:

```bash
# "Wired connection 2" is the active profile on enp8s0; confirm with `nmcli connection show --active`
nmcli connection modify "Wired connection 2" \
  ipv4.method manual \
  ipv4.addresses 192.168.1.10/24 \
  ipv4.gateway 192.168.1.1 \
  ipv4.dns 192.168.1.3
nmcli connection up "Wired connection 2"
```

`ipv4.method manual` pins the address instead of taking a lease. `ipv4.dns 192.168.1.3` keeps the PiHole as the resolver, which is currently required because the fiber box still advertises itself for DNS ([PiHole setup](../../../docs/systems/network/pihole-dns-setup.md)).

After both exist, run `tofu init -reconfigure`. The bucket and key are unchanged, so no state migration is needed.

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

**The workstation must be up to run OpenTofu.** The state lives on a machine that is not always on. Any `tofu` command needs the workstation online and reachable on the LAN — including during disaster recovery, where bringing the workstation and MinIO up is a prerequisite to rebuilding the cluster from code.
