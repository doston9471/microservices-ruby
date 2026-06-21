# Step 8: Health Probes

**Goal:** Add **liveness** and **readiness** probes so Kubernetes knows when Rails is healthy and when to send traffic.

**Time:** ~20 minutes.

**Prerequisites:**

- [Step 7 – Persistent Storage](./07-persistent-storage.md) — both services running with PVCs

---

## Why probes?

Without probes, Kubernetes only knows the container process started — not whether Rails is actually serving requests.

| Probe | Question it answers | If it fails |
|-------|---------------------|-------------|
| **Readiness** | Is the app ready for traffic? | Pod removed from Service endpoints (no traffic) |
| **Liveness** | Is the app still alive? | Container restarted |

Rails ships a health endpoint:

```ruby
# config/routes.rb
get "up" => "rails/health#show", as: :rails_health_check
```

Returns **200** when the app boots cleanly, **500** on failure.

---

## What we add

Both Deployments get HTTP probes on port **80** (Thruster), path **`/up`**:

```yaml
readinessProbe:
  httpGet:
    path: /up
    port: 80
  initialDelaySeconds: 15
  periodSeconds: 10
  timeoutSeconds: 3
  failureThreshold: 3

livenessProbe:
  httpGet:
    path: /up
    port: 80
  initialDelaySeconds: 30
  periodSeconds: 20
  timeoutSeconds: 5
  failureThreshold: 3
```

---

## Probe timing explained

Rails runs `db:prepare` on boot (via `docker-entrypoint`), so the app needs time before `/up` succeeds.

| Field | Readiness | Liveness | Why |
|-------|-----------|----------|-----|
| `initialDelaySeconds` | 15 | 30 | Wait for Rails + DB before first check |
| `periodSeconds` | 10 | 20 | How often to probe |
| `timeoutSeconds` | 3 | 5 | Max wait per probe |
| `failureThreshold` | 3 | 3 | Failures before action |

**Readiness** starts checking sooner — traffic flows once `/up` returns 200.

**Liveness** waits longer on first boot to avoid killing a slow-starting container.

---

## 1. Apply updated Deployments

Probes are in `k8s/service1/deployment.yaml` and `k8s/service2/deployment.yaml`.

```bash
kubectl apply -f k8s/service1/deployment.yaml
kubectl apply -f k8s/service2/deployment.yaml
kubectl rollout status deployment/users-service -n microservices
kubectl rollout status deployment/products-service -n microservices
```

No image rebuild needed — this is a manifest-only change.

---

## 2. Verify probes are configured

```bash
kubectl get pods -n microservices
```

Wait until both show `READY 1/1`.

Inspect probe config:

```bash
kubectl describe pod -n microservices -l app=users-service | grep -A2 "Liveness\|Readiness"
```

Expected:

```
Liveness:     http-get http://:80/up delay=30s timeout=5s period=20s #success=1 #failure=3
Readiness:    http-get http://:80/up delay=15s timeout=3s period=10s #success=1 #failure=3
```

Check conditions:

```bash
kubectl describe pod -n microservices -l app=users-service | grep -A6 "^Conditions:"
```

`Ready: True` and `ContainersReady: True` mean probes passed.

---

## 3. Test the health endpoint manually

```bash
kubectl port-forward -n microservices svc/users-service 3000:80
```

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/up
# Expected: 200
```

Same for products on port 3001.

---

## Readiness in action

When readiness fails, the Pod stays running but **stops receiving traffic** from the Service.

Simulate (optional learning exercise):

1. Watch endpoints while a Pod restarts:

```bash
kubectl get endpoints users-service -n microservices -w
```

2. In another terminal:

```bash
kubectl rollout restart deployment/users-service -n microservices
```

During rollout you may briefly see endpoints change as the old Pod goes NotReady and the new Pod becomes Ready.

---

## Liveness in action

When liveness fails repeatedly, Kubernetes **restarts the container**.

You rarely test this manually. Common real causes:

- Deadlocked Puma process
- Out-of-memory kill (may need separate handling)
- App hung after boot

Check restart count:

```bash
kubectl get pods -n microservices
# RESTARTS column — should stay 0 under normal operation
```

---

## Liveness vs Readiness vs Startup

| Probe | Use when |
|-------|----------|
| **Startup** | Very slow boot (optional) — disables liveness until it passes |
| **Readiness** | App ready for requests |
| **Liveness** | App still healthy after boot |

Rails with `db:prepare` on first start can use a **startupProbe** if liveness kills the container too early:

```yaml
startupProbe:
  httpGet:
    path: /up
    port: 80
  failureThreshold: 30
  periodSeconds: 5
# livenessProbe runs only after startupProbe succeeds
```

Our `initialDelaySeconds` values are enough for this tutorial. Add `startupProbe` if you see restarts during cold boot.

---

## Rails-specific notes

### `/up` and `force_ssl`

Production enables `force_ssl`, but kubelet probes use plain HTTP to port 80. Your app already returns 200 on `/up` over HTTP (Thruster handles it). `silence_healthcheck_path = "/up"` reduces log noise from probes.

### Thruster on 80, Puma on 3000

Probes target port **80** (Thruster), not Puma's internal 3000.

---

## Troubleshooting

### Pod stuck `0/1 Ready` but logs show server started

- Increase `readinessProbe.initialDelaySeconds`
- Check `kubectl describe pod` → Events for probe failures
- Test manually: `kubectl exec ... -- wget -qO- http://127.0.0.1:80/up`

### `CrashLoopBackOff` with restarts increasing

Liveness may be too aggressive:

- Increase `livenessProbe.initialDelaySeconds`
- Or add `startupProbe` (see above)

### Probe returns 301/302 instead of 200

SSL redirect intercepting `/up`. Uncomment in `production.rb`:

```ruby
config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }
```

Rebuild image if you change Rails config.

### Readiness fails after PVC mount issues

If the app cannot write to `storage/`, `/up` may return 500. Check volume permissions (`fsGroup: 1000`) from Step 7.

---

## Useful commands

```bash
kubectl describe pod -n microservices -l app=users-service
kubectl get events -n microservices --sort-by='.lastTimestamp'
kubectl get pods -n microservices -w
```

---

## Repeat later (checklist)

- [ ] Probes in both `deployment.yaml` files (`/up` on port 80)
- [ ] `kubectl apply` both Deployments
- [ ] Pods reach `1/1 Ready`
- [ ] `kubectl describe pod` shows Liveness and Readiness probes
- [ ] `curl http://localhost:3000/up` → 200 via port-forward

---

## Next step

**Step 9:** Expose services with **Ingress** (optional) — route traffic from your Mac without separate port-forwards.

See: [09-ingress.md](./09-ingress.md)
