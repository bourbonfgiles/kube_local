# Learning path

Lessons on top of the platform. Everything is an upstream Helm chart deployed
by Flux; you write Flux objects and values, never application code. Each file
says what you end up with, what it maps to on EKS, the tasks, how to tell
you're done, and where it gets hard.

| # | File | You end up with | Needs | Effort |
| --- | --- | --- | --- | --- |
| 1 | [01-cilium.md](01-cilium.md) | A Gateway and routes by hand, Hubble flows | Platform | Small |
| 2 | [02-flux.md](02-flux.md) | Flux syncing this repo; the Gateway and podinfo from Git | 1 | Medium |
| 3 | [03-external-dns.md](03-external-dns.md) | Routes get real `*.kube.internal` names | 2 | Medium |
| 4 | [04-cert-manager.md](04-cert-manager.md) | HTTPS on the Gateway, trusted by your browser | 2, 3 | Medium-large |
| 5 | [05-sops.md](05-sops.md) | Secrets encrypted in Git | 2 | Medium |
| 6 | [06-monitoring.md](06-monitoring.md) | Prometheus, Grafana, Cilium and Hubble metrics | 2, Cilium under Flux | Large |
| 7 | [07-registry.md](07-registry.md) | Upstream images mirrored into the local ECR stand-in | Platform | Small |
| 8 | [08-image-promotion.md](08-image-promotion.md) | Flux promoting mirrored tags and committing them to Git | 2, 7 | Medium-large |
| 9 | [09-flagger.md](09-flagger.md) | Automated canaries through the Gateway | 2, 6 | Large |
| 10 | [10-otel-demo.md](10-otel-demo.md) | A 20-service shop with traces, routes per service, Kafka | 2, 3 | Medium |
| 11 | [11-keda.md](11-keda.md) | The shop's Kafka consumer scaled on lag | 10 | Medium |
| 12 | [12-karpenter.md](12-karpenter.md) | Karpenter provisioning simulated nodes | 2, 7 | Large |
| 13 | [13-minecraft.md](13-minecraft.md) | A Java server you can join and profile with BPF | 2 | Small |

## Working in k9s

Every lesson's objects have a k9s view: type `:` and the resource's plural
name (`:helmreleases`, `:kustomizations`, `:gateways`, `:httproutes`,
`:certificates`, `:scaledobjects`, `:nodeclaims`). `d` describes (status and
events are where failures explain themselves), `l` logs, `s` a shell,
`Shift-f` a port-forward for UIs like Grafana or Hubble, `:xray deploy <ns>` a
dependency tree. The `flux` CLI covers what k9s can't: `flux reconcile`,
`flux suspend`, `flux diff`, `flux trace`.

## Ground rules

- Once Flux is in, change things through Git. Flux reverts manual changes.
- Pin every chart and image version.
- Keep base values (what you'd use on EKS) apart from local ones, as `cilium/`
  and `overlays/local/` already do.
- When something's stuck, `flux get all -A`, `flux events -A`, and `d` on the
  object in k9s usually say why. The repo README's Troubleshooting table
  covers the platform.

## More lessons

Each is one or two charts and a clear thing to learn.

Platform and GitOps

- **Flux notifications**: `Provider` and `Alert` objects posting reconcile
  failures to Discord or Slack.
- **Flux multi-tenancy**: a tenant namespace with its own service account and
  a `Kustomization` that can only touch it.
- **Headlamp or Capacitor**: a Flux-aware UI alongside k9s.
- **Cluster upgrade drill**: bump k3s a minor in the dotfiles config, rebuild,
  and let Flux restore everything. Then the same for a Cilium minor.

Security, with eBPF

- **Tetragon**: Cilium's eBPF runtime security. Trace process execs and file
  access in pods; pairs with the BPF Performance Tools book.
- **Kyverno**: policies such as "images only from the local registry" or
  "every Deployment has limits", in audit then enforce mode.
- **Trivy Operator**: vulnerability and config reports for everything running,
  as CRDs you can browse in k9s.
- **Network policy hardening**: default-deny a namespace, then allow only what
  Hubble shows is needed.

AWS stand-ins

- **MinIO** as S3, then **Velero** backing up namespaces to it and restoring
  into a rebuilt cluster.
- **CloudNativePG** as RDS: a Postgres cluster, failover, and backups to MinIO.
- **LocalStack** for SQS/SNS-style services, if its licence suits.

Observability and resilience

- **Loki and Alloy**: logs next to the metrics from lesson 6.
- **Chaos Mesh**: kill pods, add latency, partition the network, and watch
  the OpenTelemetry Demo and Flagger react.
- **PodDisruptionBudgets and topology spread**: drain nodes with
  `kubectl drain` and see which workloads survive. The agents carry zone
  labels for this.
- **VPA with Goldilocks**: recommendations for requests and limits from real
  usage.
