# Step 2: kubectl Basics

**Goal:** Learn the `kubectl` commands you will use in every later step — contexts, namespaces, inspecting resources, logs, and running commands inside Pods.

**Time:** ~30–45 minutes (read + hands-on exercises).

**Prerequisites:**

- [Step 0 – Kubernetes Mental Model](./00-kubernetes-mental-model.md)
- [Step 1 – Cluster Setup](./01-cluster-setup.md) — cluster `microservices` running

**Cluster context for this guide:** `kind-microservices`

---

## Before you start

Confirm you are talking to the right cluster:

```bash
kubectl config current-context
# Expected: kind-microservices

kubectl get nodes
# Expected: microservices-control-plane   Ready
```

If you see a different context (e.g. `rancher-desktop`), switch:

```bash
kubectl config use-context kind-microservices
```

---

## How kubectl commands are structured

Most commands follow this pattern:

```
kubectl <action> <resource-type> <name> [flags]
```

Examples:

```bash
kubectl get pods
kubectl get pod coredns-589f44dc88-fbj89 -n kube-system
kubectl describe pod coredns-589f44dc88-fbj89 -n kube-system
kubectl logs coredns-589f44dc88-fbj89 -n kube-system
```

**Resource type shortcuts:**

| Full name | Short |
|-----------|-------|
| `pods` | `po` |
| `services` | `svc` |
| `deployments` | `deploy` |
| `namespaces` | `ns` |
| `nodes` | `no` |

---

## 1. Contexts — which cluster am I using?

Your machine can have multiple cluster configurations. Each **context** = cluster + user + optional default namespace.

### List contexts

```bash
kubectl config get-contexts
```

Example (your machine may also show other contexts):

```
CURRENT   NAME                 CLUSTER              AUTHINFO             NAMESPACE
*         kind-microservices   kind-microservices   kind-microservices
          rancher-desktop      rancher-desktop      rancher-desktop
```

The `*` marks the active context.

### Switch context

```bash
kubectl config use-context kind-microservices
```

### View full kubeconfig

```bash
kubectl config view
```

You rarely edit this by hand; `kind` created the `kind-microservices` entry when you ran `kind create cluster`.

---

## 2. Namespaces — logical folders

A **namespace** groups resources so names do not collide and you can organize workloads.

### List namespaces

```bash
kubectl get namespaces
# or shorthand:
kubectl get ns
```

On your cluster you should see at least:

| Namespace | Purpose |
|-----------|---------|
| `default` | Where your apps go if you do not specify a namespace |
| `kube-system` | Kubernetes system components (CoreDNS, kube-proxy, …) |
| `kube-public` | Public cluster info |
| `kube-node-lease` | Node heartbeat data |
| `local-path-storage` | Storage provisioner (from kind) |

Later we will create `microservices` for your Rails apps.

### Set default namespace for current context (optional)

```bash
kubectl config set-context --current --namespace=default
```

After this, you can omit `-n default` on commands. To reset:

```bash
kubectl config set-context --current --namespace=
```

### Create and delete a practice namespace

```bash
kubectl create namespace practice
kubectl get ns practice
kubectl delete namespace practice
```

Deleting a namespace removes **everything** inside it.

---

## 3. `get` — list resources

The most common command. Use it constantly to see what is running.

### Pods in all namespaces

```bash
kubectl get pods -A
# -A is shorthand for --all-namespaces
```

### Pods in kube-system (system components)

```bash
kubectl get pods -n kube-system
```

### More detail with `-o wide`

Shows node, IP, and which container image is running:

```bash
kubectl get pods -n kube-system -o wide
```

Example output:

```
NAME                                       READY   STATUS    RESTARTS   AGE   IP           NODE
coredns-589f44dc88-fbj89                   1/1     Running   0          15h   10.244.0.4   microservices-control-plane
coredns-589f44dc88-r8z4c                   1/1     Running   0          15h   10.244.0.3   microservices-control-plane
...
```

**Column meanings:**

| Column | Meaning |
|--------|---------|
| `READY` | Containers ready / total containers in Pod |
| `STATUS` | `Running`, `Pending`, `CrashLoopBackOff`, etc. |
| `RESTARTS` | How often containers restarted |
| `IP` | Pod IP inside the cluster (changes when Pod is recreated) |
| `NODE` | Which node runs this Pod |

### Watch for changes (live updates)

```bash
kubectl get pods -n kube-system --watch
```

Press `Ctrl+C` to stop.

### Other useful `get` commands

```bash
kubectl get nodes
kubectl get svc -A
kubectl get deploy -A
kubectl get events -n kube-system --sort-by='.lastTimestamp'
```

`events` are especially helpful when a Pod is stuck in `Pending` or `CrashLoopBackOff`.

### Output as YAML or JSON

Useful when writing your own manifests:

```bash
kubectl get pod -n kube-system coredns-589f44dc88-fbj89 -o yaml
kubectl get deploy -n kube-system coredns -o yaml
```

---

## 4. Labels and selectors

Resources have **labels** (key/value tags). You filter with `-l`:

```bash
# All CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Show labels on pods
kubectl get pods -n kube-system --show-labels
```

When we deploy Rails services, we will use labels like `app=users-service` to connect Services to Pods.

---

## 5. `describe` — detailed troubleshooting view

When `get` is not enough, `describe` shows events, container state, mounts, probes, and errors.

```bash
kubectl describe pod -n kube-system coredns-589f44dc88-fbj89
```

**What to look for:**

| Section | Tells you |
|---------|-----------|
| `Status` | `Running`, `Pending`, `Failed` |
| `Containers` → `State` | Why a container exited |
| `Conditions` | `Ready`, `Initialized` |
| `Events` (bottom) | Scheduler/volume/image pull errors |

Describe a node:

```bash
kubectl describe node microservices-control-plane
```

Describe a namespace:

```bash
kubectl describe namespace kube-system
```

---

## 6. `logs` — container stdout/stderr

Pods write application output to logs. This is how you debug Rails apps later.

### Recent log lines

```bash
kubectl logs -n kube-system coredns-589f44dc88-fbj89 --tail=10
```

Example output:

```
maxprocs: Leaving GOMAXPROCS=8: CPU quota undefined
.:53
[INFO] plugin/reload: Running configuration SHA512 = ...
CoreDNS-1.14.2
linux/arm64, go1.26.1, dd1df4f
```

### Follow logs live (like `tail -f`)

```bash
kubectl logs -n kube-system coredns-589f44dc88-fbj89 -f
```

Press `Ctrl+C` to stop following (does not stop the Pod).

### Logs from a previous crashed container

```bash
kubectl logs <pod-name> -n <namespace> --previous
```

Useful when a Pod is in `CrashLoopBackOff`.

### Logs by label (multiple Pods)

```bash
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=5
```

---

## 7. `exec` — run a command inside a Pod

Opens a shell or runs a one-off command inside a running container — like `docker exec`.

### One-off command

Some minimal images (e.g. CoreDNS) do not include `sh` or `cat`. Use a small debug Pod instead:

```bash
kubectl run debug --image=busybox:1.36 --restart=Never -- sleep 3600
kubectl wait --for=condition=Ready pod/debug --timeout=60s
kubectl exec debug -- sh -c "echo hello from inside the cluster"
```

Expected:

```
hello from inside the cluster
```

### Interactive shell

```bash
kubectl exec -it debug -- sh
```

Inside the shell you can run:

```sh
# DNS inside the cluster (CoreDNS service IP is often 10.96.0.10)
nslookup kubernetes.default.svc.cluster.local

# Exit the shell
exit
```

### Clean up the debug Pod

```bash
kubectl delete pod debug
```

---

## 8. Creating and deleting resources imperatively (learning only)

For Steps 3+, we will use **YAML manifests** (`kubectl apply -f`). For practice, imperative commands are fine:

```bash
# Create a Pod
kubectl run nginx --image=nginx:alpine --port=80

# Check it
kubectl get pod nginx

# Delete it
kubectl delete pod nginx
```

`kubectl run` is a shortcut; production workflows prefer `Deployment` YAML files.

---

## Hands-on exercise (15 minutes)

Run these in order. Use your actual CoreDNS pod name if it differs (`kubectl get pods -n kube-system`).

```bash
# 1. Confirm context
kubectl config current-context

# 2. List system pods
kubectl get pods -n kube-system

# 3. Pick a CoreDNS pod name and describe it
kubectl describe pod -n kube-system -l k8s-app=kube-dns | head -50

# 4. Read its logs
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=5

# 5. Debug pod + exec (tests exec and cluster DNS)
kubectl run debug --image=busybox:1.36 --restart=Never -- sleep 3600
kubectl wait --for=condition=Ready pod/debug --timeout=60s
kubectl exec debug -- sh -c "echo hello from inside the cluster"
kubectl exec debug -- sh -c "nslookup kubernetes.default.svc.cluster.local"
kubectl delete pod debug

# 6. Practice namespace
kubectl create namespace practice
kubectl get ns practice
kubectl delete namespace practice
```

If step 5 prints `hello from inside the cluster` and `nslookup` resolves `kubernetes.default.svc.cluster.local` to an IP (e.g. `10.96.0.1`), cluster DNS is working.

> **Why not `wget http://kubernetes...`?** The built-in `kubernetes` Service points at the API server, which only accepts **HTTPS** on port 443. `wget http://...` tries port 80 and returns `Connection refused` — that is expected, not a broken cluster.

Optional — reach the API over HTTPS (advanced):

```bash
kubectl run debug --image=busybox:1.36 --restart=Never -- sleep 3600
kubectl wait --for=condition=Ready pod/debug --timeout=60s
kubectl exec debug -- sh -c "wget -qO- --no-check-certificate https://kubernetes.default.svc.cluster.local/version" | head -c 200
kubectl delete pod debug
```

Expected: JSON starting with `{"major":`.

---

## Cheat sheet (pin this)

### Daily commands

```bash
kubectl config current-context
kubectl config use-context kind-microservices
kubectl get pods -A
kubectl get pods -n <namespace>
kubectl get pods -n <namespace> -o wide
kubectl describe pod <name> -n <namespace>
kubectl logs <name> -n <namespace> --tail=50
kubectl logs <name> -n <namespace> -f
kubectl exec -it <name> -n <namespace> -- sh
kubectl delete pod <name> -n <namespace>
```

### Applying manifests (coming in Step 4+)

```bash
kubectl apply -f path/to/manifest.yaml
kubectl delete -f path/to/manifest.yaml
kubectl get all -n <namespace>
```

### When something is wrong

```bash
kubectl describe pod <name> -n <namespace>    # read Events at the bottom
kubectl logs <name> -n <namespace> --previous # if container crashed
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

### Help

```bash
kubectl get --help
kubectl explain pod
kubectl explain pod.spec.containers
```

`kubectl explain` documents YAML fields — very useful when writing manifests.

---

## Common Pod statuses

| Status | Typical cause |
|--------|----------------|
| `Pending` | Scheduling delay, image pull, or waiting for volume |
| `Running` | At least one container is running |
| `CrashLoopBackOff` | Container starts, crashes, Kubernetes retries |
| `ImagePullBackOff` | Wrong image name or registry auth |
| `Error` | Container failed to start |
| `Completed` | Container ran and exited successfully (Jobs) |

Always run `kubectl describe pod` and check **Events**.

---

## Tips for your Rails project (preview)

| Later step | kubectl you will use |
|------------|----------------------|
| Deploy service2 | `kubectl apply -f k8s/...`, `kubectl get deploy,po,svc` |
| Secrets | `kubectl create secret`, `kubectl describe secret` |
| Test API | `kubectl port-forward svc/users-service 3000:80` |
| Debug Rails | `kubectl logs -l app=users-service`, `kubectl exec` into Pod |

`port-forward` bridges a port on your Mac to a Pod or Service in the cluster — we use it heavily before Ingress.

---

## Troubleshooting

### `The connection to the server ... was refused`

Cluster is not running:

```bash
docker ps | grep microservices-control-plane
kind get clusters
# Recreate if needed:
kind create cluster --name microservices
```

### `error: context ... does not exist`

```bash
kind export kubeconfig --name microservices
kubectl config use-context kind-microservices
```

### Wrong cluster / empty results

```bash
kubectl config get-contexts
kubectl config use-context kind-microservices
```

### `NotFound` for pod name

Pod names include random suffixes and change when recreated. List first:

```bash
kubectl get pods -n kube-system
```

Or use labels:

```bash
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=5
```

### `exec`: executable not found

The container image is minimal. Use `busybox` or your app image for shell access.

---

## Repeat later (checklist)

- [ ] `kubectl config current-context` → `kind-microservices`
- [ ] `kubectl get ns`
- [ ] `kubectl get pods -n kube-system`
- [ ] `kubectl describe pod -n kube-system -l k8s-app=kube-dns`
- [ ] `kubectl logs -n kube-system -l k8s-app=kube-dns --tail=5`
- [ ] Create `debug` busybox pod, `exec`, delete
- [ ] Create and delete `practice` namespace

---

## Next step

**Step 3:** Build Docker images for `service1` and `service2`, then load them into the kind cluster so Kubernetes can run them.

See: [03-build-and-load-images.md](./03-build-and-load-images.md)
