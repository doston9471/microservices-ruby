# Step 6: Deploy service1 (Users) & Cross-Service Calls

**Goal:** Deploy the Users Rails app to Kubernetes, then verify service1 calls service2 over cluster DNS (`GET /api/v1/products`).

**Time:** ~30–45 minutes.

**Prerequisites:**

- [Step 5 – Secrets & ConfigMaps](./05-secrets-and-config.md)
- `products-service` running in namespace `microservices`
- `ProductService` updated to use `PRODUCTS_SERVICE_URL` (Step 5)

---

## Architecture after this step

```mermaid
flowchart LR
    mac[Your Mac curl :3000]
    usvc[users-service Service]
    upod[users-service Pod]
    psvc[products-service Service]
    ppod[products-service Pod]

    mac -->|port-forward| usvc
    usvc --> upod
    upod -->|HTTP PRODUCTS_SERVICE_URL| psvc
    psvc --> ppod
```

| Request | Path |
|---------|------|
| `curl localhost:3000/api/v1/users` | Users Pod → SQLite (users DB) |
| `curl localhost:3000/api/v1/products` | Users Pod → `http://products-service` → Products Pod |

---

## New files

```
k8s/service1/
├── configmap.yaml      # from Step 5 (PRODUCTS_SERVICE_URL)
├── deployment.yaml
├── service.yaml
└── secret.yaml.example
```

---

## 1. Confirm prerequisites

Both images built and loaded:

```bash
kubectl config use-context kind-microservices
docker images | grep -E 'service[12]:local'
kind get clusters

kubectl get deploy,svc -n microservices
# products-service should be Running
```

Rebuild service1 if `ProductService` or credentials changed:

```bash
docker build -t service1:local ./service1
kind load docker-image service1:local --name microservices
```

---

## 2. Align credentials (service1 repo)

`RAILS_MASTER_KEY` must decrypt `config/credentials.yml.enc` **in the image**, and credentials must include `secret_key_base`.

If the Pod crashes with `InvalidMessage` or `Missing secret_key_base`, regenerate a matched pair in `service1/`:

```bash
cd service1
git checkout main

# Remove mismatched pair (only if fixing credentials)
rm -f config/master.key config/credentials.yml.enc

# Create credentials with secret_key_base (using the built image)
docker run --rm -v "$(pwd):/rails" -w /rails service1:local sh -c \
  'KEY=$(bin/rails secret); printf "secret_key_base: %s\n" "$KEY" | EDITOR="tee" bin/rails credentials:edit'
```

Then:

1. Commit `config/credentials.yml.enc` in the **service1** submodule (never commit `master.key`).
2. Rebuild and reload the image (section 1).

---

## 3. Apply ConfigMap

```bash
kubectl apply -f k8s/service1/configmap.yaml
```

Verify `PRODUCTS_SERVICE_URL`:

```bash
kubectl get configmap users-service-config -n microservices -o yaml
```

Expected:

```yaml
data:
  PRODUCTS_SERVICE_URL: http://products-service
```

---

## 4. Create Secret

```bash
kubectl create secret generic users-service-secrets \
  --from-literal=RAILS_MASTER_KEY="$(cat service1/config/master.key)" \
  -n microservices
```

Or update if it exists:

```bash
kubectl create secret generic users-service-secrets \
  --from-literal=RAILS_MASTER_KEY="$(cat service1/config/master.key)" \
  -n microservices \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

## 5. Deploy Deployment + Service

```bash
kubectl apply -f k8s/service1/deployment.yaml
kubectl apply -f k8s/service1/service.yaml
```

Wait for rollout:

```bash
kubectl rollout status deployment/users-service -n microservices
kubectl get pods -n microservices -l app=users-service
```

Expected:

```
NAME                             READY   STATUS    RESTARTS   AGE
users-service-xxxxxxxxxx-xxxxx   1/1     Running   0          30s
```

Check env inside the Pod:

```bash
kubectl exec -n microservices deploy/users-service -- sh -c \
  'echo PRODUCTS_SERVICE_URL=$PRODUCTS_SERVICE_URL; test -n "$RAILS_MASTER_KEY" && echo RAILS_MASTER_KEY=set'
```

---

## 6. Test from your Mac

**Terminal 1:**

```bash
kubectl port-forward -n microservices svc/users-service 3000:80
```

**Terminal 2:**

```bash
# Health
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/up
# Expected: 200

# Users API (local DB in Pod)
curl http://localhost:3000/api/v1/users
# Expected: []

# Cross-service: Users → Products over cluster DNS
curl http://localhost:3000/api/v1/products
# Expected: JSON array (empty [] or products if seeded)
```

### Optional: seed data

Create a product (directly on Products):

```bash
kubectl port-forward -n microservices svc/products-service 3001:80
# other terminal:
curl -X POST -H "Content-Type: application/json" \
  -d '{"product":{"name":"Book","price":"19.99"}}' \
  http://localhost:3001/api/v1/products
```

Then through Users (cross-service):

```bash
curl http://localhost:3000/api/v1/products
```

You should see the same product data — proof that `users-service` reached `products-service` inside the cluster.

Create a user:

```bash
curl -X POST -H "Content-Type: application/json" \
  -d '{"user":{"name":"John","email":"john@example.com"}}' \
  http://localhost:3000/api/v1/users
```

---

## Manifest summary

### `deployment.yaml`

Same pattern as Products:

```yaml
image: service1:local
imagePullPolicy: Never
envFrom:
  - configMapRef:
      name: users-service-config
  - secretRef:
      name: users-service-secrets
```

### `service.yaml`

```yaml
metadata:
  name: users-service
spec:
  selector:
    app: users-service
  ports:
    - port: 80
      targetPort: 80
```

### `ProductService` (service1 code)

```ruby
base_url = ENV.fetch("PRODUCTS_SERVICE_URL", "http://localhost:3001")
```

| Environment | `PRODUCTS_SERVICE_URL` | Result |
|-------------|------------------------|--------|
| Local dev | unset | `http://localhost:3001` |
| Kubernetes | `http://products-service` | cluster DNS |

---

## View both services

```bash
kubectl get all -n microservices
```

```bash
kubectl get deploy,svc,pods -n microservices
```

---

## Troubleshooting

### `InvalidMessage` on boot

`master.key` does not match `credentials.yml.enc` in the image. See section 2.

### `Missing secret_key_base`

Credentials file exists but has no `secret_key_base` key. Regenerate with section 2 command (includes `bin/rails secret`).

### `Products service unavailable` in JSON response

```bash
# From users Pod — can it reach products?
kubectl exec -n microservices deploy/users-service -- sh -c \
  'wget -qO- http://products-service/api/v1/products'
```

Check:

- `PRODUCTS_SERVICE_URL` is `http://products-service` (not `localhost`)
- `products-service` Deployment is Running
- ConfigMap applied and Deployment restarted after ConfigMap edits

### Users works locally but not cross-service

Rebuild image after `ProductService` change and `rollout restart`:

```bash
docker build -t service1:local ./service1
kind load docker-image service1:local --name microservices
kubectl rollout restart deployment/users-service -n microservices
```

---

## What to commit

| Repo | Files |
|------|-------|
| **service1** (submodule) | `app/services/product_service.rb`, `config/credentials.yml.enc` (if regenerated) |
| **microservices-ruby** | `k8s/service1/deployment.yaml`, `k8s/service1/service.yaml`, this doc |

Update parent repo submodule pointer after service1 commits:

```bash
git add service1
git commit -m "Update service1 submodule"
```

---

## Repeat later (checklist)

- [ ] `products-service` Running
- [ ] `service1` credentials aligned (`master.key` + `credentials.yml.enc` with `secret_key_base`)
- [ ] `docker build` + `kind load` for `service1:local`
- [ ] `kubectl apply -f k8s/service1/configmap.yaml`
- [ ] Secret `users-service-secrets` with `RAILS_MASTER_KEY`
- [ ] `kubectl apply -f k8s/service1/deployment.yaml -f k8s/service1/service.yaml`
- [ ] `kubectl port-forward svc/users-service 3000:80`
- [ ] `curl localhost:3000/api/v1/products` returns products from service2

---

## Next step

**Step 7:** Add PersistentVolumeClaims so SQLite databases survive Pod restarts.

See: [07-persistent-storage.md](./07-persistent-storage.md) *(next session)*
