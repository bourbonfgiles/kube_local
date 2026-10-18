# Learning path

Tasks to work through on top of the platform. Each file says what you end up
with, what it maps to on EKS, the tasks, how to tell you're done, and where it
gets hard. None of it is pre-built.

| # | File | You end up with | Needs | Effort |
| --- | --- | --- | --- | --- |
| 1 | [01-cilium.md](01-cilium.md) | A hand-written Gateway and routes, Hubble flows | Platform | Small |
| 2 | [02-flux.md](02-flux.md) | Flux syncing this repo; the Gateway and a first app from Git | 1 | Medium |
| 3 | [03-external-dns.md](03-external-dns.md) | Routes get real `*.kube.internal` names | 2 | Medium |
| 4 | [04-cert-manager.md](04-cert-manager.md) | HTTPS on the Gateway, trusted by your browser | 2, 3 | Medium-large |
| 5 | [05-sops.md](05-sops.md) | Secrets encrypted in Git | 2 | Medium |
| 6 | [06-monitoring.md](06-monitoring.md) | Prometheus, Grafana, Cilium and Hubble metrics | 2, Cilium under Flux | Large |
| 7 | [07-registry.md](07-registry.md) | Your images in the local ECR stand-in | Platform | Small |
| 8 | [08-image-promotion.md](08-image-promotion.md) | Flux bumping tags and committing them to Git | 2, 7 | Medium-large |
| 9 | [09-karpenter.md](09-karpenter.md) | Karpenter provisioning simulated nodes | 2, 7 | Large |
| 10 | [10-app-bookinfo.md](10-app-bookinfo.md) | Microservices with path, header and weighted routes | 1-4 | Medium |
| 11 | [11-app-events.md](11-app-events.md) | Your own producer and consumer on NATS, scaled by KEDA | 2, 7, 8 | Large |
| 12 | [12-app-minecraft.md](12-app-minecraft.md) | A Java server you can join and profile with BPF | 2 | Small |

Apps (10-12) can start as soon as their dependencies are done; they don't have
to wait for 9.

Ground rules that apply throughout:

- Once Flux is in, change things through Git. Flux reverts manual changes.
- Pin every chart and image version.
- Keep base values (what you'd use on EKS) apart from local ones, as `cilium/`
  and `overlays/local/` already do.
- When something breaks, `flux get all -A`, `flux events -A` and `kubectl
  describe` on the stuck object usually say why. The repo README's
  Troubleshooting table covers the platform.
