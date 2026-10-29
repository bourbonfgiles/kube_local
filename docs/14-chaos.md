# 14. Chaos Mesh with an on/off switch

> You end up with: scheduled experiments that kill pods, add latency and burn
> CPU in the shop, all switched on and off by one value in Git.

## What it is

Chaos engineering is breaking things on purpose, on a schedule, to find out
what copes before a real failure does it for you. Netflix's Chaos Monkey
started it by killing instances at random. **Chaos Mesh** does the same inside
Kubernetes, with an experiment kind per kind of failure:

| Kind | Breaks |
| --- | --- |
| `PodChaos` | Kills pods or containers, or makes them fail |
| `NetworkChaos` | Adds latency, loss, duplication or a partition between pods |
| `StressChaos` | Burns CPU or memory inside a container |
| `IOChaos`, `TimeChaos`, `DNSChaos`... | Slow disks, skewed clocks, wrong DNS answers |
| `Schedule` | Runs any of the above on a cron schedule |

```mermaid
flowchart LR
  sched["Schedule pod-kill<br/>@every 5m"] --> ctrl["chaos-controller-manager"]
  ctrl -->|"creates"| exp["PodChaos"]
  exp --> daemon["chaos-daemon<br/>on the target's node"]
  daemon -->|"kill / tc / stress<br/>via containerd"| pod["Target pod"]
  dash["chaos-dashboard :2333"] --> ctrl
```

The controller decides what to break; a privileged **chaos-daemon** on every
node does it, reaching containers through the container runtime. A `Schedule`
is paused when it carries `experiment.chaos-mesh.org/pause: "true"`; any other
value runs it. That's the switch this lesson builds.

## On EKS

AWS Fault Injection Service for AWS-level faults (terminate instances, throttle
APIs), or Chaos Mesh/Litmus on EKS for pod-level ones. On EKS the runtime is
containerd at its default socket, so the k3s socket setting below goes away.

## Requirements

**In the cluster**: Flux (lesson 2) and something worth breaking: the
OpenTelemetry Demo (lesson 10) shows failures clearly in Jaeger and Grafana.

**On your machine**: `kubectl`, `helm`, `flux`, `git`, `k9s`, `sofka`.

## Install by hand

### 1. Chaos Mesh

```yaml
# scratch/14/values-local.yaml
chaosDaemon:
  runtime: containerd
  socketPath: /run/k3s/containerd/containerd.sock   # k3s's, not the default
dashboard:
  securityMode: false   # no login; local only
```

```sh
helm --kube-context k3d-dev upgrade --install chaos-mesh chaos-mesh --repo https://charts.chaos-mesh.org \
  --version 2.8.5 -n chaos-mesh --create-namespace -f scratch/14/values-local.yaml
```

k9s `:pods -n chaos-mesh`: the controller, the dashboard, and a
`chaos-daemon` on every node. `Shift-f` on `chaos-dashboard` port 2333 for
the UI.

### 2. One experiment, once

Before scheduling anything, kill one pod by hand:

```yaml
# scratch/14/pod-kill.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: kill-one
  namespace: otel-demo
spec:
  action: pod-kill
  mode: one
  selector:
    namespaces: [otel-demo]
    labelSelectors:
      app.kubernetes.io/component: cart
```

```sh
kubectl --context k3d-dev apply -f scratch/14/pod-kill.yaml
```

k9s `:pods -n otel-demo`: a `cart` pod restarts. `d` on the PodChaos shows the
record. Delete it before applying again: a one-off experiment runs once.

### 3. Iterate

Edit, delete, re-apply:

| Try | Then look at |
| --- | --- |
| Drop `labelSelectors` | A random demo pod dies each time. Which ones does the shop notice? |
| `mode: fixed-percent`, `value: "50"` | Half the namespace at once |
| `action: container-kill`, `containerNames: [cart]` | The container restarts; the pod survives |
| A `NetworkChaos` (below) on `cart` | Slow spans in Jaeger for the next two minutes |

<details>
<summary>200ms latency on cart for two minutes</summary>

```yaml
# scratch/14/latency.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: cart-latency
  namespace: otel-demo
spec:
  action: delay
  mode: all
  selector:
    namespaces: [otel-demo]
    labelSelectors:
      app.kubernetes.io/component: cart
  delay:
    latency: 200ms
  duration: 2m
```

</details>

Check the label in `:pods -n otel-demo` (`d`, Labels) if a selector matches
nothing.

**Where to look**

| Check | kubectl | k9s | sofka |
| --- | --- | --- | --- |
| Chaos Mesh up | `kubectl --context k3d-dev get pods -n chaos-mesh` | `:pods -n chaos-mesh` | `:pods -n chaos-mesh` |
| The dashboard | `kubectl --context k3d-dev -n chaos-mesh port-forward svc/chaos-dashboard 2333` | `:svc -n chaos-mesh`, `Shift-f` | `:svc -n chaos-mesh`, `f` |
| The experiment's record | `kubectl --context k3d-dev -n otel-demo describe podchaos kill-one` | `d` | `d` |
| What a selector matches | `kubectl --context k3d-dev -n otel-demo get pods -l app.kubernetes.io/component=cart` | `:pods -n otel-demo`, `/-l app.kubernetes.io/component=cart` | The same |
| What broke, in order | `kubectl --context k3d-dev get events -n otel-demo --sort-by=.lastTimestamp` | `:events -n otel-demo` | `T` on `cart`'s Deployment |
| Schedules (Flux part) | `kubectl --context k3d-dev get schedules -n chaos` | `:schedules -n chaos` | `:schedules -n chaos` |
| Suspend the `chaos` Kustomization (exercise 3) | `flux --context k3d-dev suspend kustomization chaos` | `Shift-t` (plugin) | `t` |

> [!TIP]
> This is where sofka's timeline earns its keep. Open `:workloads otel-demo`
> before you flip the switch: `ctrl-z` keeps only what's hurt right now, `T`
> on a Deployment says when it lost pods and when it had them back, and
> `:bundle` on it writes the incident up for you.

### 4. Clean up

```sh
kubectl --context k3d-dev delete -f scratch/14/ --ignore-not-found
helm --kube-context k3d-dev uninstall chaos-mesh -n chaos-mesh
```

## Install with Flux

| Kind | Name | File |
| --- | --- | --- |
| Namespace | `chaos-mesh` | `infrastructure/base/chaos-mesh/namespace.yaml` |
| HelmRepository | `chaos-mesh` | `infrastructure/base/chaos-mesh/source.yaml` |
| HelmRelease | `chaos-mesh` | `infrastructure/base/chaos-mesh/release.yaml` |
| ConfigMap | `chaos-mesh-values-local` | `infrastructure/local/chaos-mesh/values.yaml` |
| HTTPRoute | `chaos-mesh/dashboard` | `infrastructure/local/chaos-mesh/route.yaml` |
| Kustomization | `flux-system/chaos` | `clusters/dev/chaos.yaml` |
| Namespace, Schedules | `chaos` | `chaos/*.yaml` |

1. **The chart.** HelmRelease `chart: chaos-mesh`, `version: 2.8.5`,
   `valuesFrom` only the local ConfigMap, holding
   `scratch/14/values-local.yaml`. Route: `chaos.kube.internal` to Service
   `chaos-dashboard` port 2333.
2. **The switch.** Experiments get their own folder and Kustomization, so one
   variable reaches all of them, and so they apply only after the CRDs exist:
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
   `postBuild.substitute` replaces `${CHAOS_PAUSED}` in every file under
   `./chaos` before applying. `${CHAOS_PAUSED:=true}` means "true if unset".
3. **Experiments on a schedule**, each with the annotation:
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
   Plus `chaos/namespace.yaml` for `chaos`, and `chaos/latency.yaml`: the
   NetworkChaos from above as `type: NetworkChaos` with
   `schedule: "@every 15m"`.
4. Push. `:schedules -n chaos` shows them, paused.

> [!WARNING]
> Don't `kubectl apply` files from `chaos/` by hand. Without Flux, the
> annotation is the literal string `${CHAOS_PAUSED:=true}`, which isn't
> `"true"`, so the Schedule runs. To check one is valid, use
> `kubectl --context k3d-dev apply --dry-run=server -f chaos/pod-kill.yaml`.

## Exercises

1. Flip `CHAOS_PAUSED` to `"false"` and push. Watch `:pods -n otel-demo`, the
   dashboard's timeline and Jaeger. Flip it back: no new experiments start;
   running ones finish their `duration`.
2. A `StressChaos` schedule burning CPU in one service, and find it in
   Grafana.
3. Emergency stop without Git. Suspend first, or Flux puts the old value back:
   ```sh
   flux --context k3d-dev suspend kustomization chaos
   kubectl --context k3d-dev -n chaos annotate schedules --all \
     experiment.chaos-mesh.org/pause=true --overwrite
   ```
   Fix Git, then `flux --context k3d-dev resume kustomization chaos`.
4. Harder: decide which demo services cope with losing a pod and which don't,
   then fix one with `replicas: 2` and a PodDisruptionBudget in its values, and
   prove it with the same experiment.

## Where it gets hard

- The chart's default runtime is Docker. Without the containerd settings the
  daemon can't find containers and every experiment fails to inject.
- Annotation values are strings. Quote `"${CHAOS_PAUSED:=true}"`, or YAML
  makes `true` a boolean and the object is rejected.
- `chaos-daemon` runs privileged in the host's PID namespace. That's normal
  for Chaos Mesh, and a reason it stays off clusters you don't own.
- Scope selectors to namespaces you mean. One that matches `kube-system` takes
  the cluster down with it.
- `NetworkChaos` uses `tc` inside the pod's network namespace. It's untested
  here alongside Cilium's BPF programs; Hubble shows whether delays land.

A lighter alternative is kube-monkey: opt-in by label, kills pods on a
schedule, and nothing else.

## Links

- <https://chaos-mesh.org/docs/basic-features/>
- <https://chaos-mesh.org/docs/production-installation-using-helm/>
- <https://chaos-mesh.org/docs/define-scheduling-rules/>
- <https://fluxcd.io/flux/components/kustomize/kustomizations/#post-build-variable-substitution>
