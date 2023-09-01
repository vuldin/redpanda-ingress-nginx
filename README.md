Enable LoadBalancer via MetalLB:

```
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.10/config/manifests/metallb-native.yaml
kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=90s
kubectl apply -f ~/projects/redpanda/kind-config-lb.yaml
```

Install ingress-nginx:

```
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace
```

Wait until ready:

```
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

Add rp-kafka / rp-admin ports to deployment/ingress-nginx-controller:

```
        ports:
        - containerPort: 9094
          name: rp-kafka
          protocol: TCP
        - containerPort: 9644
          name: rp-admin
          protocol: TCP
```

Add externa-rp-kafka / external-rp-admin ports to service/ingress-nginx-controller:

```
  ports:
  - name: external-rp-kafka
    port: 9094
    protocol: TCP
    targetPort: rp-kafka
  - name: external-rp-admin
    port: 9644
    protocol: TCP
    targetPort: rp-admin
```