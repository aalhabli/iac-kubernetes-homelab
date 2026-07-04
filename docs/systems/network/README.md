# Host/Bare-Metal Networking Systems

Configuration references and manual setup guides for foundational networking infrastructure that runs **outside** of Kubernetes.

This includes:
- Physical switch and VLAN configuration
- DNS resolution (e.g., PiHole LXC configs)
- Tailscale host-level routing
- Cloudflare Tunnel setup (if run as a host daemon)

*Note: In-cluster networking components like MetalLB, Ingress controllers, or Cilium CNI are documented alongside their manifests in the `kubernetes/` directories.*
