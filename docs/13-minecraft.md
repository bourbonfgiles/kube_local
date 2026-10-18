# 13. Minecraft (Java)

A real JVM workload you can join from a game client, and a good subject for the
BPF Performance Tools book.

## Before you start

On your machine:

- `kubectl`, `flux`, `k9s`, `git`.
- `bpftrace` and the BCC tools in `/usr/share/bcc/tools/`: the dotfiles `bpf`
  step, then a reboot.
- A Minecraft Java client, for joining.

In the cluster: Flux (lesson 2). About 3 GB of spare memory. Host port 25565
is already mapped to NodePort 30000 by the dotfiles k3d config.

## Objects

All in namespace `minecraft`.

| Kind | Name | File |
| --- | --- | --- |
| Namespace | `minecraft` | `apps/base/minecraft/namespace.yaml` |
| HelmRepository | `itzg` | `apps/base/minecraft/source.yaml` |
| HelmRelease | `minecraft` | `apps/base/minecraft/release.yaml` |
| ConfigMap | `minecraft-values-base` | `apps/base/minecraft/values.yaml` |
| ConfigMap | `minecraft-values-local` | `apps/local/minecraft/values.yaml` |

## Tasks

1. HelmRepository `url: https://itzg.github.io/minecraft-server-charts/`,
   HelmRelease `minecraft`, `chart: minecraft`, `version: 5.2.0`.
2. Base values (`minecraft-values-base`):
   ```yaml
   minecraftServer:
     eula: "TRUE"          # you accept the Minecraft EULA
     type: VANILLA
     version: "26.3"
     memory: 2048M
     jvmXXOpts: "-XX:+PreserveFramePointer"
   resources:
     requests: {cpu: 500m, memory: 2560Mi}
     limits: {memory: 3Gi}
   persistence:
     dataDir:
       enabled: true
       Size: 5Gi           # capital S in this chart
   ```
   Local values (`minecraft-values-local`), because the port mapping is k3d's.
   On EKS this would be a `LoadBalancer` Service instead:
   ```yaml
   minecraftServer:
     serviceType: NodePort
     nodePort: 30000
   ```
3. Push and watch the first start in k9s (`l` on the pod): it downloads the
   server jar, so external DNS from pods has to work.
4. Join from a client at this machine's LAN address, port 25565.
5. The server console. k9s `:pods -n minecraft`, `s`:
   ```sh
   # in the pod shell
   rcon-cli list
   rcon-cli tps
   ```
6. Profile from the host. Rootful Podman shares the host's PID view, so the
   JVM is a normal process here:
   ```sh
   PID=$(pgrep -f '^java .*minecraft_server')
   sudo /usr/share/bcc/tools/offcputime -p "$PID" 10
   sudo /usr/share/bcc/tools/profile -p "$PID" -F 49 -f 30 > mc.folded
   ```
7. Java frames show as hex until the JVM writes a perf map. In the pod shell:
   ```sh
   # in the pod shell
   jcmd 1 Compiler.perfmap
   ```
   That writes `/tmp/perf-1.map` inside the container. BCC looks for
   `/tmp/perf-<host PID>.map` on the host, so copy it across:
   ```sh
   sudo cp /proc/$PID/root/tmp/perf-1.map /tmp/perf-$PID.map
   ```
   Then run `profile` again.
8. A flame graph from the folded output:
   ```sh
   git clone https://github.com/brendangregg/FlameGraph ~/repos/FlameGraph
   ~/repos/FlameGraph/flamegraph.pl mc.folded > mc.svg
   ```
   Open `mc.svg` in Zen (copy it to `~/Downloads` first).
9. Lower the memory limit below the heap in base values and watch the OOM kill
   in k9s (`d` on the pod) and with `sudo /usr/share/bcc/tools/oomkill`.

## Done when

- You can join, and you have a flame graph with Java method names in it.

## Where it gets hard

- Port 25565 is reachable from your LAN. That's how friends join, and also
  anyone else on the network.
- The world lives on the node's disk and goes with the cluster.
- Heap (`memory`) plus JVM overhead must fit under the limit, or it gets
  OOM-killed under load rather than at start.
- `pgrep` without `^java` matches the wrapper process, not the JVM.
- The perf map is a snapshot: methods compiled after `jcmd` ran show as hex
  until you run it again.

## Links

- <https://github.com/itzg/minecraft-server-charts>
- <https://docker-minecraft-server.readthedocs.io/>
- <https://www.brendangregg.com/bpf-performance-tools-book.html>
- <https://github.com/brendangregg/FlameGraph>
