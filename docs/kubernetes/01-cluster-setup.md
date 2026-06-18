# Step 1: Install Tools & Create a Local Cluster

**Goal:** Install Docker, `kubectl`, and `kind`; create a local Kubernetes cluster named `microservices`; verify everything works.

**Time:** ~15–30 minutes (first run may take longer while kind downloads the node image).

**Prerequisites:** [Step 0 – Kubernetes Mental Model](./00-kubernetes-mental-model.md)

---

## What you are installing

| Tool | Purpose |
|------|---------|
| **Docker** | Builds container images; kind runs the cluster inside Docker containers |
| **kubectl** | CLI to talk to any Kubernetes cluster |
| **kind** | “Kubernetes IN Docker” — creates a throwaway local cluster for learning |

---

## 1. Install Docker

### macOS (recommended: Docker Desktop)

1. Download [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop/) (Apple Silicon or Intel).
2. Install and open Docker Desktop.
3. Wait until the whale icon shows **Docker is running**.

### Verify

```bash
docker --version
# Example: Docker version 29.5.3, build d1c06ef

docker info
# Should show Server info without errors
```

If `docker info` fails, start Docker Desktop and try again.

---

## 2. Install kubectl

`kubectl` is the Kubernetes command-line tool. You use it for every later step.

### macOS (Homebrew)

```bash
brew install kubectl
```

### Verify

```bash
kubectl version --client
```

Example output:

```
Client Version: v1.34.1
Kustomize Version: v5.7.1
```

The client version does not need to match the cluster version exactly; minor differences are fine for learning.

---

## 3. Install kind

### macOS (Homebrew)

```bash
brew install kind
```

### Verify

```bash
kind version
```

Example output:

```
kind v0.32.0 go1.25.5 darwin/arm64
```

---

## 4. Create the cluster

From any directory:

```bash
kind create cluster --name microservices
```

**What happens:**

1. kind downloads a node image (`kindest/node:v1.x.x`) — **only on first run**; can take 1–3 minutes.
2. kind starts a Docker container that acts as your Kubernetes node + control plane.
3. kind configures `kubectl` to use a new context: `kind-microservices`.

Example successful output:

```
Creating cluster "microservices" ...
 • Ensuring node image (kindest/node:v1.36.1) 🖼  ...
 ✓ Ensuring node image (kindest/node:v1.36.1) 🖼
 • Preparing nodes 📦   ...
 ✓ Preparing nodes 📦
 • Writing configuration 📜  ...
 ✓ Writing configuration 📜
 • Starting control-plane 🕹️  ...
 ✓ Starting control-plane 🕹️
 • Installing CNI 🔌  ...
 ✓ Installing CNI 🔌
 • Installing StorageClass 💾  ...
 ✓ Installing StorageClass 💾
Set kubectl context to "kind-microservices"
You can now use your cluster with:

kubectl cluster-info --context kind-microservices
```

---

## 5. Verify the cluster

Run these commands in order.

### Cluster info

```bash
kubectl cluster-info
```

Expected (your port number will differ):

```
Kubernetes control plane is running at https://127.0.0.1:53771
CoreDNS is running at https://127.0.0.1:53771/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

### Current context

```bash
kubectl config current-context
```

Expected:

```
kind-microservices
```

### Node is Ready

```bash
kubectl get nodes
```

Expected:

```
NAME                          STATUS   ROLES           AGE   VERSION
microservices-control-plane   Ready    control-plane   1m    v1.36.1
```

If `STATUS` is `NotReady`, wait 30–60 seconds and run again. The node finishes booting shortly after creation.

Optional — wait explicitly:

```bash
kubectl wait --for=condition=Ready node/microservices-control-plane --timeout=90s
```

### System pods are running

```bash
kubectl get pods -A
```

You should see pods in `kube-system` (CoreDNS, etcd, kube-proxy, etc.) and `local-path-storage` with `STATUS` **Running** and `READY` **1/1**.

Example:

```
NAMESPACE            NAME                                                  READY   STATUS
kube-system          coredns-...                                           1/1     Running
kube-system          etcd-microservices-control-plane                      1/1     Running
kube-system          kindnet-...                                           1/1     Running
kube-system          kube-apiserver-microservices-control-plane            1/1     Running
kube-system          kube-controller-manager-microservices-control-plane   1/1     Running
kube-system          kube-proxy-...                                        1/1     Running
kube-system          kube-scheduler-microservices-control-plane            1/1     Running
local-path-storage   local-path-provisioner-...                            1/1     Running
```

**You are done with Step 1 when all of the above checks pass.**

---

## Understanding your cluster

### One node, one Docker container

kind creates a single Docker container named `microservices-control-plane`. Inside it runs:

- The **control plane** (API server, scheduler, etc.)
- A **worker node** that can run your application Pods

For learning, one node is enough.

### Contexts

`kubectl` can talk to multiple clusters. Each cluster has a **context**.

```bash
# List contexts
kubectl config get-contexts

# Switch to our learning cluster
kubectl config use-context kind-microservices
```

Always confirm you are on the right cluster before applying manifests:

```bash
kubectl config current-context
```

### StorageClass (useful later)

kind installs `local-path-provisioner`, which gives you a default **StorageClass** for PersistentVolumeClaims. We will use this in Step 7 for SQLite storage.

```bash
kubectl get storageclass
```

Expected: a `standard` (or similar) class marked `(default)`.

---

## Useful kind commands

```bash
# List local kind clusters
kind get clusters

# Export kubeconfig for a cluster (usually automatic)
kind export kubeconfig --name microservices

# Delete the cluster (full cleanup)
kind delete cluster --name microservices
```

---

## Troubleshooting

### `docker: command not found` or `Cannot connect to the Docker daemon`

- Open **Docker Desktop** and wait until it is running.
- Run `docker info` again.

### `kind: command not found`

- Install with `brew install kind`.
- Open a new terminal so your `PATH` picks up Homebrew.

### Node stuck in `NotReady`

```bash
kubectl describe node microservices-control-plane
```

Wait 1–2 minutes after cluster creation. If still `NotReady`, delete and recreate:

```bash
kind delete cluster --name microservices
kind create cluster --name microservices
```

### Wrong kubectl context

If commands fail or show unexpected clusters:

```bash
kubectl config use-context kind-microservices
kubectl cluster-info
```

### Cluster already exists

```
ERROR: failed to create cluster: node(s) already exist for a cluster with the name "microservices"
```

Either use the existing cluster (`kubectl config use-context kind-microservices`) or delete first:

```bash
kind delete cluster --name microservices
kind create cluster --name microservices
```

### Port conflicts

Rare on first setup. If `kind create cluster` fails with port errors, ensure no other kind cluster is using the same ports, or delete old clusters with `kind delete cluster --name <name>`.

---

## Cleanup (when you want to start over)

```bash
# Remove only the Kubernetes cluster (Docker Desktop stays installed)
kind delete cluster --name microservices
```

To recreate from scratch:

```bash
kind create cluster --name microservices
kubectl get nodes
```

---

## What we did on this machine (2026-06-17)

| Item | Value |
|------|-------|
| Docker | 29.5.3 (Docker Desktop) |
| kubectl client | v1.34.1 |
| kind | v0.32.0 |
| Cluster name | `microservices` |
| Context | `kind-microservices` |
| Kubernetes version | v1.36.1 |
| Node | `microservices-control-plane` — **Ready** |

---

## Repeat later (checklist)

Use this when setting up on a new Mac or after a long break:

- [ ] Docker Desktop running (`docker info`)
- [ ] `kubectl version --client`
- [ ] `kind version`
- [ ] `kind create cluster --name microservices`
- [ ] `kubectl config current-context` → `kind-microservices`
- [ ] `kubectl get nodes` → `Ready`
- [ ] `kubectl get pods -A` → system pods `Running`

---

## Next step

**Step 2:** Learn `kubectl` basics — contexts, namespaces, `get`, `describe`, `logs`, and `exec` — using the system pods already running in your cluster.

See: [02-kubectl-basics.md](./02-kubectl-basics.md)
