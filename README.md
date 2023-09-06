This guide shows how to setup external access through a single Nginx Ingress to a Redpanda cluster deployed onto Kubernetes via the helm chart.

## Prerequisites

You will need [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/) and [rpk](https://docs.redpanda.com/current/get-started/rpk-install/) installed.

You will need a Kubernetes cluster associated with your current kubeconfig context. If you need to set such a cluster up locally, then you can do so by [installing kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installing-from-release-binaries). Once installed, then run the following commands:

```
kind create cluster --name jlp-cluster --config kind-config.yaml
```

Your Kubernetes cluster must have a LoadBalancer controller. If you don't already have one, then the following commands will install MetalLB:

```
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.10/config/manifests/metallb-native.yaml
kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=90s
kubectl apply -f kind-config-lb.yaml
```

You must also have TLS certificates configured appropriately within a secret named `tls-external` in the namespace where you will deploy Redpanda. In this example, we will use the namespace `redpanda`. If you don't have certificates (or if you want to see how certificates should be turned into the appropriate secret), then follow the commands below to create the secret using self-signed certificates:

```
./generate-certs.sh
```

The above command generates a self-signed certificate/key for Redpanda brokers and the associated certificate authority. These files are located in the `certs` folder:

```
> tree certs
certs
├── 01.pem
├── ca.crt
├── ca.key
├── node.crt
└── node.key

0 directories, 5 files
```

If you have your own files, then make sure they are either in the same location and names in the same way, or you must change the following command to match your file locations. The following command will create a secret based on the above file structure that will be used in both the Redpanda helm chart config and the `ingress-nginx` helm chart config:

```
kubectl create secret generic tls-external --from-file=ca.crt=certs/ca.crt --from-file=tls.crt=certs/node.crt --from-file=tls.key=certs/node.key --dry-run=client -o yaml > tls-external.yaml
kubectl create ns redpanda
kubectl apply -f tls-external.yaml -n redpanda
```

The secret created above will be called `tls-external`. If you change the name of this secret then make sure to update the values.yaml files for both helm chart deployments.

## Deploy Redpanda

Deploy Redpanda:

```
helm upgrade --install redpanda redpanda --repo https://charts.redpanda.com -n redpanda --wait --timeout 1h -f redpanda-values.yaml
```

### Verify Redpanda

> Note: You can skip this section if you have already gone through these steps successfully.

Verify the kafka port is configured correctly for TLS and advertised listeners:

```
kubectl exec -it -n redpanda redpanda-0 -c redpanda -- rpk cluster info --brokers localhost:9094 --tls-enabled --tls-truststore /etc/tls/certs/external/ca.crt
```

You will see the hostnames used as the advertised listener endpoints in the output. The default output is:

```
CLUSTER
=======
redpanda.d68cb2f0-91ad-439c-aa39-4901a508e9ef

BROKERS
=======
ID    HOST              PORT
0*    redpanda-0.local  9094
1     redpanda-1.local  9094
2     redpanda-2.local  9094
```

The domain for these hostnames are based off the `external.domain` value found in [redpanda-values.yaml](./redpanda-values.yaml#L7).

Verify the admin port is configured correctly for for internal clients:

```
kubectl exec -it -n redpanda redpanda-0 -c redpanda -- rpk cluster health --api-urls localhost:9644
```

> Note: The admin port is configured for internal clients only, as it would be a security concern if it were made available to external clients. This is also why there is only one admin listener available.

Verify the schema registry port is configured correctly for TLS connections:

```
kubectl exec -it -n redpanda redpanda-0 -c redpanda -- curl -svk --cacert /etc/tls/certs/external/ca.crt "https://localhost:8084/subjects"
```

You will see similar output to the following:

```
*   Trying 127.0.0.1:8084...
* Connected to localhost (127.0.0.1) port 8084 (#0)
* ALPN: offers h2,http/1.1
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.3 (OUT), TLS change cipher, Change cipher spec (1):
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.3 (IN), TLS handshake, Encrypted Extensions (8):
* TLSv1.3 (IN), TLS handshake, Certificate (11):
* TLSv1.3 (IN), TLS handshake, CERT verify (15):
* TLSv1.3 (IN), TLS handshake, Finished (20):
* TLSv1.3 (OUT), TLS handshake, Finished (20):
* SSL connection using TLSv1.3 / TLS_AES_128_GCM_SHA256
* ALPN: server did not agree on a protocol. Uses default.
* Server certificate:
*  subject: O=Redpanda
*  start date: Sep  6 21:08:26 2023 GMT
*  expire date: Sep  5 21:08:26 2024 GMT
*  issuer: O=Redpanda; CN=Redpanda CA
*  SSL certificate verify result: unable to get local issuer certificate (20), continuing anyway.
* using HTTP/1.x
> GET /subjects HTTP/1.1
> Host: localhost:8084
> User-Agent: curl/7.88.1
> Accept: */*
> 
< HTTP/1.1 200 OK
< Content-Length: 2
< Content-Type: application/vnd.schemaregistry.v1+json
< Date: Wed, 06 Sep 2023 21:34:41 GMT
< Server: Seastar httpd
< 
* Connection #0 to host localhost left intact
[]
```

Verify the HTTP proxy endpoint is secured by TLS with the following command:

```
kubectl exec -it -n redpanda redpanda-0 -c redpanda -- curl --ssl-reqd --cacert /etc/tls/certs/external/ca.crt https://redpanda-0.redpanda.redpanda.svc.cluster.local.:8083/brokers
```

You will see the following output:

```
{"brokers":[0,1,2]}
```

## Install the Nginx Ingress controller

The first command below installs the community-led Nginx Ingress controller via helm, and the second command waits for the deployment to be ready:

```
helm upgrade --install ingress-nginx ingress-nginx --repo https://kubernetes.github.io/ingress-nginx --namespace ingress-nginx --create-namespace -f ingress-nginx-values.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s
```

Each broker hostname must be resolvable to the external IP of the `ingress-nginx` LoadBalancer service. Get this IP with the following command:

```
kubectl get svc/ingress-nginx-controller -n ingress-nginx
```

You will get output similar to the following:

```
NAME                       TYPE           CLUSTER-IP    EXTERNAL-IP   PORT(S)                      AGE
ingress-nginx-controller   LoadBalancer   10.96.18.44   172.18.0.10   80:31974/TCP,443:30945/TCP   23m
```

If you are testing locally, then you can add each broker's hostname to your `/etc/hosts` file. Below are the lines you would add given the IP address above and the default external domain `local`:

```
> tail -3 /etc/hosts
172.18.0.10 redpanda-0.local
172.18.0.10 redpanda-1.local
172.18.0.10 redpanda-2.local
```

Edit the deployment with the following command:

```
kubectl edit deployment.apps/ingress-nginx-controller -n ingress-nginx
```

Add the following port definitions to the first (and only) container in the `containers` list:

```
spec:
  template:
    spec:
      containers:
      - ports:
        - containerPort: 8083
          name: rp-proxy
          protocol: TCP
        - containerPort: 8084
          name: rp-schema
          protocol: TCP
        - containerPort: 9094
          name: rp-kafka
          protocol: TCP
```

The deployment will automatically destroy the current pod and bring up a replacement pod with the correct configuration. Now edit the LoadBalancer service with the following command:

```
kubectl edit service/ingress-nginx-controller -n ingress-nginx
```

Add the following port definitions:

```
spec:
  ports:
  - name: external-rp-proxy
    port: 8083
    protocol: TCP
    targetPort: rp-proxy
  - name: external-rp-schema
    port: 8084
    protocol: TCP
    targetPort: rp-schema
  - name: external-rp-kafka
    port: 9094
    protocol: TCP
    targetPort: rp-kafka
```

## Deploy the Ingress service

You can now deploy the Ingress service into the `redpanda` namespace:

```
kubectl apply -f redpanda-ingress.yaml
```

### Validate Nginx Ingress

> Note: You can skip this section if you have already gone through these steps successfully.

Create an rpk profile:

```
rpk profile create ingress-nginx-redpanda -s brokers=redpanda-0.local:9094 -s tls.ca="$(realpath ./certs/ca.crt)"
```

Now you should be able to successfully run the following commands:

```
rpk cluster info
```

`rpk` commands that make use of the admin port (such as `rpk cluster health`) will not work with your external rpk client, as the admin port is only available within the cluster. Run admin-oriented `rpk` commands in the following way:

```
kubectl exec -it -n redpanda redpanda-0 -c redpanda -- rpk cluster health
```

Verify connectivity to the schema endpoint through the Ingress:

```
curl -svk --cacert certs/ca.crt "https://redpanda-0.local:8084/subjects" 
```

Verify connectivity to the HTTP proxy endpoint through the Ingress:

```
curl -sk --cacert certs/ca.crt https://redpanda-0.local:8083/brokers
```

## Cleanup

Delete self-signed certificates:

```
./delete-certs.sh
```

If you deployed a local kind cluster and want to delete it, then run the following command. Please note that this will delete the entire Kubernetes cluster (with Redpanda and the Ingress controller included):

```
kind delete cluster --name jlp-cluster
```
