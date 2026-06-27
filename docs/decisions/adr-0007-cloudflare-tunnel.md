# External Access Strategy — Tiered Exposure via Cloudflare Tunnel and Tailscale

* Status: Accepted
* Date: 2026-06-27

## Context and Problem Statement
Different workloads need to be reachable from different places, and treating them all the same is a mistake. A public website (**alhabli.com**) must be served to anyone on the internet. Admin surfaces (Proxmox, ArgoCD, Grafana, SSH) must be reachable only by me. And a personal photo library (**Immich**) must reach my own phone from anywhere but should never be public. The lab sits on a residential connection — dynamic IP, possibly CGNAT — where opening inbound router ports is a security liability and often impossible. We need a single, coherent strategy that routes each workload through the *right* door rather than forcing everything through one.

## Alternatives Considered
* **Port forwarding + Dynamic DNS for everything:** Open 80/443 on the router, point a DDNS record at the home IP.
* **One method for all services** (e.g., Cloudflare Tunnel for literally everything, including Immich and admin UIs).
* **VPN-only for everything:** No public exposure at all, even the website.
* **A tiered model:** Match each workload to an exposure mechanism based on audience and traffic profile.

## Decision
We will adopt a **three-tier external-access model**. No inbound router ports are ever opened; the home IP is never exposed directly.

| Tier | Workloads | Mechanism | Why |
|---|---|---|---|
| **Public web** | `alhabli.com`, light HTML-centric apps | **Cloudflare Tunnel** (`cloudflared`) | Outbound-only tunnel → no open ports, home IP hidden, edge CDN/WAF/DDoS protection. Ideal for HTML/static traffic. |
| **Private / admin** | Proxmox UI, ArgoCD, Grafana, SSH | **Tailscale** (WireGuard overlay) | Never public; reachable only from devices on my tailnet. Right tool for surfaces that should have *zero* public footprint. |
| **Large-media personal** | **Immich** (photo/video) | **Tailscale** (private) | Deliberately *not* Cloudflare — its proxy caps request bodies (100 MB Free / 200 MB Pro / 500 MB Business) and its ToS (§2.8) disallows disproportionate non-HTML media. Tailscale has neither limit and keeps the library private. |

Internal TLS for all of the above is issued by **cert-manager via Let's Encrypt DNS-01 against the Cloudflare API**, so certificates can be minted without any service being publicly reachable.

### Rationale
* **No inbound ports, ever — for the public tier.** `cloudflared` dials *out* to Cloudflare and traffic is served back down that tunnel. The home router keeps every inbound port closed, and public DNS points at Cloudflare, not at my house — concealing the residential IP and getting DDoS/WAF protection for free. This is the headline property and the reason port-forwarding is rejected outright (it exposes the home IP, needs open ports, and dies behind CGNAT).
* **Right door for each audience.** A public website, a private admin panel, and a personal phone-sync app have genuinely different threat models and traffic profiles. Forcing them through one mechanism either over-exposes the private ones or breaks the heavy one. The tiered model is the [ADR-0003](adr-0003-workload-placement.md) "right tool for the job" principle applied to networking.
* **Immich is the instructive exception.** Routing a photo/video library through the Cloudflare proxy fails on two hard limits — the per-request body cap (large videos/RAW files simply won't upload) and the non-HTML media ToS. A tunnel hostname can't be selectively un-proxied, so the cap is unavoidable. Tailscale sidesteps both: the phone joins the tailnet and talks to Immich's private address with no size limit and no public surface. On **Android**, the **native Immich app** does reliable background backup the moment the device is on the tailnet, so no extra sync plumbing is needed and no public photo-sharing is required.
* **Tailscale over raw WireGuard for the private tiers.** Tailscale is WireGuard with key exchange and NAT traversal automated — far less to maintain than hand-rolled WireGuard, while remaining a private, encrypted overlay with no public exposure.
* **One Cloudflare token, three jobs.** Because the domain is on Cloudflare, a single API token drives the tunnel, `external-dns`, and cert-manager's DNS-01 challenge — keeping the external-access stack coherent. That token is stored via the 1Password + ESO pipeline ([ADR-0006](adr-0006-secrets-management.md)), never in the clear.
* **Rejection of VPN-only-for-everything:** Perfect for admin and Immich, but it can't serve a genuinely public website to anonymous visitors — which is the entire point of alhabli.com.
* **Rejection of one-method-for-all:** Either exposes admin UIs publicly (bad) or pushes Immich through Cloudflare's media limits (broken). The split is the decision.

## Consequences

### Positive (What becomes easier?)
* **Secure public exposure with zero open inbound ports**, the home IP concealed, and edge protection in front of the website.
* **Resilient to a changing residential IP / CGNAT** — outbound tunnel and overlay VPN need no DDNS or port-forward upkeep.
* **Each surface uses the right door:** public web is public, admin is invisible to the internet, and Immich works from anywhere without ever being exposed.
* **Coherent TLS + DNS** driven by one Cloudflare token across tunnel, external-dns, and cert-manager.

### Negative (What becomes harder/Risks?)
* **Two access systems to operate** (Cloudflare Tunnel + Tailscale) instead of one. Accepted: each is simple and they fail independently — a Cloudflare outage doesn't touch Tailscale-reached services, and vice versa.
* **Centralization on Cloudflare for the public tier.** The website's reachability depends on Cloudflare being up and my account in good standing. The private tiers are unaffected.
* **`cloudflared` is a potential SPOF** for public services (now including a real website); mitigated by running multiple `cloudflared` replicas so the tunnel survives a pod/node failure.
* **Tailnet onboarding for household members** is required if I ever want family to reach Immich — a one-time Tailscale install per device, accepted in exchange for never exposing the library publicly.
* **Sensitive credentials** (tunnel token, Cloudflare API token, Tailscale auth keys) must all flow through [ADR-0006](adr-0006-secrets-management.md) rather than being committed or hand-placed ad hoc.
