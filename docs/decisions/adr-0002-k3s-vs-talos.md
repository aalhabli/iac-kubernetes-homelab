# Use k3s as the Kubernetes Distribution over Full k8s or Talos Linux

* Status: Accepted
* Date: 2026-06-27

## Context and Problem Statement
With the foundational Proxmox hypervisor layer established, we need a Kubernetes distribution to run our containerized workloads (Paperless, Syncthing, monitoring stack, etc.). The goal is to build a highly available (HA) 3-node cluster. We must balance the need for low overhead (to leave resources for Proxmox LXCs/VMs) with the desire for a highly educational, production-grade learning surface.

## Alternatives Considered
* **Vanilla Kubernetes (k8s / kubeadm):** The upstream, unopinionated standard.
* **Talos Linux:** A modern, secure, API-driven, immutable Kubernetes OS.
* **MicroK8s:** Canonical's low-ops Kubernetes distribution.

## Decision
We will use **k3s (by Rancher)** as our Kubernetes distribution, provisioned onto Ubuntu or Debian VMs.

### Rationale
* **Low Overhead & High Performance:** k3s is a CNCF-certified Kubernetes distribution stripped of legacy, out-of-tree cloud provider code. It packages all k8s components into a single binary, resulting in a much smaller memory and CPU footprint compared to vanilla k8s. This maximizes the 64GB of RAM we have available on the ThinkPad for actual workloads.
* **Learning Surface (The "Goldilocks" Zone):** Vanilla `kubeadm` is highly complex to bootstrap and maintain (requiring deep knowledge of etcd and PKI out of the gate), which can cause fatigue before workloads are even deployed. Talos Linux, while technically superior in its immutability, abstracts away *too much* of the underlying Linux OS. k3s provides the perfect middle ground: it handles the painful bootstrapping, but still leaves the underlying OS accessible for us to learn node-level configuration via Ansible.
* **Embedded etcd:** k3s supports High Availability using an embedded etcd datastore, removing the need to manage a separate etcd cluster.

## Consequences

### Positive (What becomes easier?)
* **Faster time-to-value:** We can deploy a cluster quickly using Ansible and start learning Kubernetes manifests and GitOps (ArgoCD) rather than fighting cluster bootstrapping issues.
* **Resource efficiency:** k3s leaves significantly more RAM and CPU available for our applications.

### Negative (What becomes harder/Risks?)
* **Opinionated defaults (LoadBalancing):** k3s ships with Klipper (ServiceLB) by default, which simply binds host ports rather than provisioning true dedicated IPs. Because we plan to use MetalLB to simulate a true enterprise bare-metal load balancer (with its own dedicated IP pool), we will need to explicitly disable `servicelb` during the Ansible bootstrapping phase using `--disable` flags. (Note: We are retaining the default Traefik ingress controller as it is highly capable and modern).
* **Not immutable:** Unlike Talos, the underlying OS can still drift. We will mitigate this by managing the node OS entirely via Ansible and OpenTofu to enforce IaC principles.
