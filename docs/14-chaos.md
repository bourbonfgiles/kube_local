# 14. Chaos with an on/off switch

Chaos Mesh, run like Netflix's Chaos Monkey: scheduled experiments that kill
random pods, add latency or burn CPU in a target namespace. All of them hang
off one flag in Git, and they're off until you flip it.

EKS equivalent: AWS Fault Injection Service, or Chaos Mesh/Litmus on EKS.

## Before you start

On your machine: `kubectl`, `flux`, `git`, `k9s`.

In the cluster: Flux (lesson 2) and something worth breaking: the
OpenTelemetry Demo (lesson 10) shows failures clearly in Jaeger and Grafana.

## Objects

| Kind | Name | File |
| --- | --- | --- |
| Namespace | `chaos-mesh` | `infrastructure/base/chaos-mesh/namespace.yaml` |
| HelmRepository | `chaos-mesh/chaos-mesh` | `infrastructure/base/chaos-mesh/source.yaml` |
| HelmRelease | `chaos-mesh/chaos-mesh` | `infrastructure/base/chaos-mesh/release.yaml` |
| ConfigMap | `chaos-mesh/chaos-mesh-values-local` | `infrastructure/local/chaos-mesh/values.yaml` |
| HTTPRoute | `chaos-mesh/dashboard` | `infrastructure/local/chaos-mesh/route.yaml` |
| Kustomization | `flux-system/chaos` | `clusters/dev/chaos.yaml` |
| Namespace | `chaos` | `chaos/namespace.yaml` |
| Schedule | `chaos/pod-kill`, `chaos/latency`, `chaos/cpu` | `chaos/<name>.yaml` |

The experiments get their own folder and Kustomization so one variable can
switch them all, and so they apply only after Chaos Mesh's CRDs exist.

## The switch

Chaos Mesh pauses a `Schedule` when it carries the annotation
`experiment.chaos-mesh.org/pause: "true"`; any other value runs it. Flux fills
that value from one variable:

- Every file in `chaos/` has `experiment.chaos-mesh.org/pause: "${CHAOS_PAUSED:=true}"`.
- The `chaos` Kustomization sets `CHAOS_PAUSED` with `postBuild.substitute`.

Change it to `"false"`, push, and experiments start. Change it back and no new
ones start; any running one finishes its `duration`. If the variable goes
missing, `:=true` keeps chaos off.

## Tasks

1. HelmRepository `url: https://charts.chaos-mesh.org`, HelmRelease
   `chaos-mesh`, `chart: chaos-mesh`, `version: 2.8.5`, `valuesFrom` only the
   local ConfigMap. Local values, because the runtime socket is k3s's:
   ```yaml
   chaosDaemon:
     runtime: containerd
     socketPath: /run/k3s/containerd/containerd.sock
   dashboard:
     securityMode: false   # no login; local only
   ```
2. Push. k9s `:pods -n chaos-mesh`: the controller, the dashboard, and a
   `chaos-daemon` on every node.
3. An HTTPRoute `chaos.kube.internal` to Service `chaos-dashboard`, port 2333.
4. The switch:
   ```yaml
   # clusters/dev/chaos.yaml
   apiVersion: kustomize.toolkit.fluxcd.io/v1
   kind: Kustomization
   metadata:
     name: chaos
     namespace: flux-system
   spec:
     dependsOn:
       - name: infra-local
     interval: 10m
     retryInterval: 1m
     sourceRef:
       kind: GitRepository
       name: flux-system
     path: ./chaos
     prune: true
     postBuild:
       substitute:
         CHAOS_PAUSED: "true"
   ```
5. Monkey, killing one demo pod every five minutes. Don't apply these by
   hand (see "Where it gets hard"); check one is accepted with
   `kubectl --context k3d-dev apply --dry-run=server -f chaos/pod-kill.yaml`
   once the `chaos` namespace exists.
   ```yaml
   # chaos/pod-kill.yaml
   apiVersion: chaos-mesh.org/v1alpha1
   kind: Schedule
   metadata:
     name: pod-kill
     namespace: chaos
     annotations:
       experiment.chaos-mesh.org/pause: "${CHAOS_PAUSED:=true}"
   spec:
     schedule: "@every 5m"
     type: PodChaos
     historyLimit: 5
     concurrencyPolicy: Forbid
     podChaos:
       action: pod-kill
       mode: one
       selector:
         namespaces: [otel-demo]
   ```
   Plus `chaos/namespace.yaml` for `chaos`. Commit and push.
6. Latency: `chaos/latency.yaml`, a Schedule of `type: NetworkChaos`,
   `networkChaos.action: delay`, `delay.latency: 200ms` on one service's pods
   (`selector.labelSelectors`), `duration: 2m`, `schedule: "@every 15m"`.
7. Pressure: `chaos/cpu.yaml`, `type: StressChaos`, a CPU stressor on one
   service.
8. Flip `CHAOS_PAUSED` to `"false"` in `clusters/dev/chaos.yaml` and push.
   Watch k9s `:pods -n otel-demo` restart, traces slow down in Jaeger, the
   dashboard's timeline fill in.
9. Flip it back and check everything recovers on its own.
10. Emergency stop without Git. Suspend first, or Flux puts the old value back:
    ```sh
    flux --context k3d-dev suspend kustomization chaos
    kubectl --context k3d-dev -n chaos annotate schedules --all \
      experiment.chaos-mesh.org/pause=true --overwrite
    ```
    Fix Git, then `flux --context k3d-dev resume kustomization chaos`.

## Done when

- One commit turns chaos on, one turns it off, and you can say which demo
  services cope with losing a pod and which don't.

## Where it gets hard

- The chart's default runtime is Docker. Without the containerd settings the
  daemon can't find containers and experiments fail to inject.
- Annotation values are strings. Quote `"${CHAOS_PAUSED:=true}"`, or YAML
  turns `true` into a boolean and the object is rejected.
- Applied by hand, the annotation is the literal string
  `${CHAOS_PAUSED:=true}`, which isn't `"true"`, so the Schedule runs. Only
  Flux substitutes it.
- `chaos-daemon` runs privileged with the host's PID namespace. That's normal
  for Chaos Mesh, and a reason it stays off clusters you don't own.
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
