# 14. Chaos with an on/off switch

Chaos Mesh, run like Netflix's Chaos Monkey: scheduled experiments that kill
random pods, add latency or burn CPU in a target namespace. All of them hang
off one flag in Git, and they're off until you flip it.

EKS equivalent: AWS Fault Injection Service, or Chaos Mesh/Litmus on EKS.

## Before you start

- Flux (lesson 2) and something worth breaking: the OpenTelemetry Demo (lesson
  10) shows failures clearly in Jaeger and Grafana.

## The switch

Chaos Mesh pauses a `Schedule` when it carries the annotation
`experiment.chaos-mesh.org/pause: "true"`; any other value runs it. Flux can
fill that value from one variable:

- Experiments live in `./chaos`, applied by their own Flux `Kustomization`.
- Every `Schedule` has `experiment.chaos-mesh.org/pause: "${CHAOS_PAUSED:=true}"`.
- That Kustomization sets `postBuild.substitute.CHAOS_PAUSED: "true"`.

Change it to `"false"`, push, and everything starts. Change it back and
everything stops, with injected faults removed. If the variable goes missing,
`:=true` keeps chaos off.

## Tasks

1. `HelmRepository` `https://charts.chaos-mesh.org`, chart `chaos-mesh`,
   namespace `chaos-mesh`. k3s values:
   ```yaml
   chaosDaemon:
     runtime: containerd
     socketPath: /run/k3s/containerd/containerd.sock
   dashboard:
     securityMode: false   # no login; local only
   ```
2. k9s `:pods -n chaos-mesh`: the controller, the dashboard, and a
   `chaos-daemon` on every node.
3. An `HTTPRoute` for the dashboard (`chaos.kube.internal`, Service
   `chaos-dashboard`, port 2333).
4. The `chaos` Kustomization with the switch above, `dependsOn` the Chaos Mesh
   HelmRelease so the CRDs exist first.
5. Monkey: a `Schedule` of type `PodChaos`, `action: pod-kill`, `mode: one`,
   selector on the demo namespace, `schedule: "@every 5m"`.
6. Latency: a `Schedule` of type `NetworkChaos`, `action: delay`, 200ms on one
   service, `duration: 2m`, every 15 minutes.
7. Pressure: a `StressChaos` schedule on one service's CPU.
8. Flip the switch to `"false"`. Watch k9s `:pods -n <demo ns>` restart,
   traces slow down in Jaeger, the dashboard's timeline fill in.
9. Flip it back and check everything recovers on its own.
10. Emergency stop without Git: `flux suspend kustomization chaos`, then
    `kubectl annotate schedules -n chaos --all experiment.chaos-mesh.org/pause=true --overwrite`.
    Suspend first, or Flux puts the old value back.

## Done when

- One commit turns chaos on, one turns it off, and you can say which demo
  services cope with losing a pod and which don't.

## Where it gets hard

- The chart's default runtime is Docker. Without the containerd settings the
  daemon can't find containers and experiments fail to inject.
- Annotation values are strings. Quote `"${CHAOS_PAUSED:=true}"`, or YAML
  turns `true` into a boolean and the object is rejected.
- `chaos-daemon` runs privileged with the host's PID namespace. That's
  normal for Chaos Mesh, and a reason it stays off clusters you don't own.
- Scope selectors to namespaces you mean. A selector that matches
  `kube-system` takes the cluster down with it.
- `NetworkChaos` uses `tc` inside the pod's network namespace. It's untested
  here alongside Cilium's own BPF programs; Hubble shows whether delays land.

A lighter alternative is kube-monkey: opt-in by label, kills pods on a
schedule, and nothing else.

## Links

- <https://chaos-mesh.org/docs/production-installation-using-helm/>
- <https://chaos-mesh.org/docs/define-scheduling-rules/>
- <https://fluxcd.io/flux/components/kustomize/kustomizations/#post-build-variable-substitution>
