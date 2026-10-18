# 13. Minecraft (Java)

A real JVM workload you can join from a game client, and a good subject for the
BPF Performance Tools book.

## Before you start

- Flux (lesson 2). About 3 GB of spare memory.
- Host port 25565 is already mapped to NodePort 30000 (dotfiles k3d config).

## Tasks

1. `HelmRepository` `https://itzg.github.io/minecraft-server-charts/`, chart
   `minecraft`.
2. Values:
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
     dataDir: {enabled: true, Size: 5Gi}
   ```
   Local overlay: `minecraftServer.serviceType: NodePort`, `nodePort: 30000`.
3. Watch the first start: it downloads the server jar, so external DNS from
   pods has to work.
4. Join from a client at this machine's LAN address.
5. `kubectl exec` into the pod and use `rcon-cli` (`list`, `tps`).
6. Profile from the host (`bpf` dotfiles step, after a reboot):
   ```sh
   PID=$(pgrep -f '^java .*minecraft_server')
   sudo /usr/share/bcc/tools/profile -p "$PID" -F 49 30 > mc.stacks
   sudo /usr/share/bcc/tools/offcputime -p "$PID" 10
   ```
7. Java frames show as hex until you add a perf map agent; the book's Java
   chapter covers it.
8. Lower the memory limit below the heap and watch the OOM kill in
   k9s (`d` on the pod) and `oomkill` from BCC.

## Done when

- You can join, and you have a flame graph with Java method names in it.

## Where it gets hard

- Port 25565 is reachable from your LAN. That's how friends join, and also
  anyone else on the network.
- The world lives on the node's disk and goes with the cluster.
- Heap (`memory`) plus JVM overhead must fit under the limit, or it gets
  OOM-killed under load rather than at start.
- `pgrep` without `^java` matches the wrapper process, not the JVM.

## Links

- <https://github.com/itzg/minecraft-server-charts>
- <https://docker-minecraft-server.readthedocs.io/>
- <https://www.brendangregg.com/bpf-performance-tools-book.html>
