# 0002. Cilium as CNI and Gateway API implementation

**Status**: Accepted. Built in lessons 1 and 2.

## Context

The cluster is created with no CNI. EKS defaults to the AWS VPC CNI with the
AWS Load Balancer Controller for ingress.

## Decision

Cilium as the CNI, with kube-proxy replacement, Gateway API, Hubble, and LB
IPAM with L2 announcements standing in for a cloud load balancer.

## Why

- One component for pod networking, Services, ingress, network policy and
  flow visibility.
- eBPF throughout, which is the same kernel machinery as the BPF tools used
  on the host (lesson 15).
- `Gateway` and `HTTPRoute` are portable: on EKS with the Load Balancer
  Controller only `gatewayClassName` changes.

## Costs

- A bad Cilium value takes the network down, and Flux with it. Recovery is
  lesson 2's: suspend the HelmRelease, rerun `bootstrap.sh`, fix Git, resume.
- Lessons 0 and 1 stay by hand: Cilium must exist before Flux can run.
- k3d needs its own settings, kept apart in `overlays/local/`.
- A plain `NetworkPolicy` can't select the Gateway's `ingress` identity; it
  takes a `CiliumNetworkPolicy`.

## On EKS

More often the VPC CNI plus the AWS Load Balancer Controller. Cilium appears
chained with the VPC CNI, or replacing it.
