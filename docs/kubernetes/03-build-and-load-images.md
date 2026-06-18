# Step 3: Build and Load Docker Images

**Goal:** Build production Docker images for `service1` and `service2`, load them into your kind cluster, and verify Kubernetes can run them.

**Time:** ~10–20 minutes (first build downloads Ruby gems; later rebuilds are faster).

**Prerequisites:**

- [Step 1 – Cluster Setup](./01-cluster-setup.md) — cluster `microservices` running
- [Step 2 – kubectl Basics](./02-kubectl-basics.md)
- Docker Desktop running

---

## What you are doing

```
service1/Dockerfile  ──docker build──►  service1:local  ──kind load──►  kind node
service2/Dockerfile  ──docker build──►  service2:local  ──kind load──►  kind node
```

1. **Build** images on your Mac with Docker.
2. **Load** images into the kind node (kind does not see your Mac’s Docker images automatically).
3. **Verify** Kubernetes can start a Pod from the loaded image.

We are **not** deploying the Rails apps yet — that is Step 4. This step is only about images.

---

## Image names we use

| Service | Folder | Image tag |
|---------|--------|-----------|
| Users (service1) | `service1/` | `service1:local` |
| Products (service2) | `service2/` | `service2:local` |

The `:local` tag signals “built on this machine for kind,” not pulled from a registry.

Later manifests will use `imagePullPolicy: Never` so Kubernetes uses the loaded image instead of trying Docker Hub.

---

## 1. Confirm prerequisites

From the `microservices-ruby` repo root:

```bash
kubectl config use-context kind-microservices
kind get clusters
# Expected: microservices

docker info
# Should succeed (Docker Desktop running)
```

---

## 2. Build service1 (Users)

```bash
cd service1
docker build -t service1:local .
```

Or from the repo root:

```bash
docker build -t service1:local ./service1
```

**What the Dockerfile does (summary):**

| Stage | Purpose |
|-------|---------|
| `base` | Ruby 3.4 slim + sqlite3 runtime packages |
| `build` | `bundle install`, copy app, bootsnap precompile |
| final | Non-root `rails` user, port 80, `docker-entrypoint` → Thruster + Puma |

First build takes several minutes. Docker caches layers; rebuilds after small code changes are much faster.

### Build fix: `libyaml-dev`

If `bundle install` fails installing the `psych` gem with `yaml.h not found`, the build stage needs `libyaml-dev`. Both Dockerfiles include:

```dockerfile
apt-get install --no-install-recommends -y build-essential git pkg-config libyaml-dev
```

If you see that error on an older copy of the Dockerfile, add `libyaml-dev` to the **build** stage (not the final stage).

---

## 3. Build service2 (Products)

```bash
docker build -t service2:local ./service2
```

---

## 4. Verify images on your Mac

```bash
docker images | grep service
```

Example:

```
service1   local   d026b0704160   ...   839MB
service2   local   83aab3a62864   ...   839MB
```

Sizes vary (~800MB+ is normal for Rails production images).

---

## 5. Load images into kind

kind runs Kubernetes **inside** Docker. Nodes do not automatically share images with your host Docker daemon. You must **load** each image:

```bash
kind load docker-image service1:local service2:local --name microservices
```

Expected output:

```
Image: "service1:local" with ID "sha256:..." not yet present on node "microservices-control-plane", loading...
Image: "service2:local" with ID "sha256:..." not yet present on node "microservices-control-plane", loading...
```

Run this again after every **rebuild** when you change app code and want Kubernetes to use the new image.

---

## 6. Verify Kubernetes can run the image

Start a throwaway Pod (not the full Rails app — we are only checking the image is present):

```bash
kubectl run image-check \
  --image=service1:local \
  --image-pull-policy=Never \
  --restart=Never \
  --command -- sleep 30

kubectl wait --for=condition=Ready pod/image-check --timeout=60s
kubectl get pod image-check
```

Expected:

```
NAME          READY   STATUS    RESTARTS   AGE
image-check   1/1     Running   0          10s
```

Clean up:

```bash
kubectl delete pod image-check
```

**Why `imagePullPolicy: Never`?** Tells Kubernetes to use the image already on the node. Without it, kubelet tries to pull `service1:local` from a registry and fails with `ErrImagePull`.

---

## About `RAILS_MASTER_KEY` (not needed yet)

The production image expects `RAILS_MASTER_KEY` at **runtime** to decrypt `config/credentials.yml.enc`. You do **not** need it to **build** the image.

| Step | master.key needed? |
|------|-------------------|
| Step 3 (build + load) | No |
| Step 4+ (run Rails server) | Yes — we add it as a Secret in Step 6 |

Each service has its own key:

```bash
# Only if the file exists locally (gitignored)
cat service1/config/master.key
cat service2/config/master.key
```

If missing, run `bin/rails credentials:edit` inside each service to generate one.

---

## Rebuild workflow (use often)

After changing Rails code:

```bash
# 1. Rebuild
docker build -t service1:local ./service1
# or service2

# 2. Reload into kind
kind load docker-image service1:local --name microservices

# 3. Later (Step 4+): restart Deployment so Pods pick up the new image
# kubectl rollout restart deployment/users-service -n microservices
```

Changing only Kubernetes YAML does not require a rebuild. Changing Ruby code does.

---

## One-shot script (optional)

From `microservices-ruby` root:

```bash
#!/usr/bin/env bash
set -euo pipefail

docker build -t service1:local ./service1
docker build -t service2:local ./service2
kind load docker-image service1:local service2:local --name microservices
echo "Done. Images loaded into kind cluster 'microservices'."
```

Save as `scripts/k8s-build-images.sh` if you want a shortcut (optional).

---

## Troubleshooting

### `Cannot connect to the Docker daemon`

Start Docker Desktop, then `docker info`.

### `bundle install` fails: `psych` / `yaml.h not found`

Add `libyaml-dev` to the Dockerfile **build** stage `apt-get install` line (see section 2).

### `kind load` fails: cluster not found

```bash
kind get clusters
kind create cluster --name microservices   # if missing
```

### Pod `ErrImagePull` or `ImagePullBackOff`

- Image not loaded: `kind load docker-image service1:local --name microservices`
- Missing `imagePullPolicy: Never` in your manifest
- Wrong image name/tag typo

### Pod `ErrImageNeverPull`

Image not present on the node. Run `kind load` again after build.

### Rebuilt image but Pod still runs old code

Loaded image updated on node, but **existing Pods** keep the old container until recreated. In Step 4+ you will `kubectl delete pod` or `rollout restart deployment`.

### Huge image size (~800MB+)

Normal for Rails + gems + Thruster. Optimizations (multi-stage, .dockerignore) are out of scope for this tutorial.

---

## What we did on this machine

| Item | Value |
|------|-------|
| Images built | `service1:local`, `service2:local` (~839MB each) |
| Loaded into | `kind` cluster `microservices` |
| Verified | `image-check` Pod reached `Running` with `imagePullPolicy: Never` |
| Dockerfile change | Added `libyaml-dev` to build stage (both services) |

---

## Repeat later (checklist)

- [ ] `kubectl config use-context kind-microservices`
- [ ] `docker build -t service1:local ./service1`
- [ ] `docker build -t service2:local ./service2`
- [ ] `docker images | grep service`
- [ ] `kind load docker-image service1:local service2:local --name microservices`
- [ ] Test Pod with `imagePullPolicy: Never` → `Running`
- [ ] Delete test Pod

---

## Next step

**Step 4:** Deploy `service2` (Products) as your first real workload — Pod, then Deployment + Service, and reach the API with `kubectl port-forward`.

See: [04-deploy-service2.md](./04-deploy-service2.md) *(next session)*
