# Nexus3 Helm Local

## Introducción

En este apartado montaremos un servicio [Nexus3](https://www.sonatype.com/products/nexus-community-edition-download) como parte de una infraestructura de laboratorio **CI/CD**.

Partimos de un servidor local con [Ubuntu 24.04LTS server](https://ubuntu.com/download/server) con [MicroK8s](https://microk8s.io/).

Este servidor conecta a Internet mediante un router local que dispone dispone de IP fija.

También disponemos de un servicio **DNS** alojado en [AWS](https://aws.amazon,es) para el dominio **_moradores.es_**

## Servicio Nexus3

El primer hito es tener un servicio **Nexus3** corriendo en el nodo **MicroK8s** con un volumen persistente de 35GB.

Para ello instalaremos el [Helm chart Nexus3](https://artifacthub.io/packages/helm/stevehipwell/nexus3) en el nodo.

Debe se accesible mediante HTTPS desde Internet. Usaremos un certificado [Let's encrypty](https://letsencrypt.org/es/). El _addon_  **Cert-Manager** de **MicroK8s** solicitará, desplegará y renovará por nosotros este certificado.

## Requisitos previos

### Configuración DNS

Crear el registro **registro A** `nexus3.moradores.es` que apunte a la IP pública del router en el servicio **Route 53** de **AWS**

- **Host**: `nexus3.moradores.es`
- **Tipo**: A
- **Dirección IP**: IP pública del router

Podemos verifica que el registro funciona, una vez creado, con la utilidad `dig` que consulta registros **DNS**

`dig nexus3.moradores.es`

Ejemplo de repuesta del comando anterior

```Text
nexus3.moradores.es.   300     IN      A       185.221.8.108

;; Query time: 39 msec
;; SERVER: 127.0.0.53#53(127.0.0.53) (UDP)
;; WHEN: Sat Nov 23 19:01:26 CET 2024
;; MSG SIZE  rcvd: 65
```

### Configuración del router

En el router local deberemos realizar la siguientes operaciones

- Redirigimos los puertos 80 (HTTP) y 443 (HTTPS) al servidor **MicroK8s**

  Ejemplo en **Mikrotik RouterOS**

  - Configura redirección de puertos:

```Bash
/ip firewall nat add chain=dstnat dst-address=185.221.8.108 protocol=tcp dst-port=80 action=dst-nat to-addresses=192.168.88.211 to-ports=80
/ip firewall nat add chain=dstnat dst-address=185.221.8.108 protocol=tcp dst-port=443 action=dst-nat to-addresses=192.168.88.211 to-ports=443
/ip firewall filter add chain=forward protocol=tcp dst-port=80,443 in-interface=pppoe-out1 dst-address=192.168.88.211 action=accept

/ip firewall nat add chain=srcnat src-address=192.168.88.0/24 dst-address=192.168.88.211 out-interface=bridge action=masquerade



```

    ```bash
      /ip firewall nat add chain=dstnat dst-address=<IP_PUBLICA> protocol=tcp dst-port=80 action=dst-nat to-addresses=<IP_PRIVADA> to-ports=80

      /ip firewall nat add chain=dstnat dst-address=<IP_PUBLICA> protocol=tcp dst-port=443 action=dst-nat to-addresses=<IP_PRIVADA> to-ports=443
    ```

    - **chain=dstnat**: Indica que estamos configurando NAT para redirección de entrada.

    - **dst-address=<IP_PUBLICA>**: La IP pública del router.

    - **protocol=tcp**: Aplica solo al protocolo TCP.

    - **dst-port=80/443**: Especifica los puertos a redirigir.

    - **action=dst-nat**: Configura redirección de tráfico.

    - **to-addresses=<IP_PRIVADA>**: IP privada del servidor local.

    - **to-ports=80/443**: Los puertos internos a redirigir.

### Configuración de MicroK8s

Nos aseguramos que **MicroK8s** tenga los _addons_ que se necesitan habilitados.

Comprobamos si  los _addons_ `dns`, `ingress`, `hostpath-storage`, `helm3`  y `cert-manager` están activos, `enabled`

```bash
  microk8s status --wait-ready
```

Activamos aquellos que no lo estén

```bash
microk8s enable hostpath-storage
microk8s enable helm3
microk8s enable cert-manager
microk8s enable ingress 
```

- **hostpath-storage**: Proporciona volúmenes persistentes

- **helm3**: Permite usar Helm para instalar nexus3

- **cert-manager**: Automatiza la gestión de certificados

- **ingress**: Habilita controladores para gestionar accesos HTTP/HTTPS

  Debemos tener en cuenta la respuesta de la activación de **cert-manager** y seguir estas instrucciones, ejemplos en la creación de los ingress con certificado

```Bash
  Cert-manager is installed. As a next step, try creating an Issuer
for Let's Encrypt by creating the following resource:

$ microk8s kubectl apply -f - <<EOF
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: letsencrypt
spec:
  acme:
    # You must replace this email address with your own.
    # Let's Encrypt will use this to contact you about expiring
    # certificates, and issues related to your account.
    email: me@example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      # Secret resource that will be used to store the account's private key.
      name: letsencrypt-account-key
    # Add a single challenge solver, HTTP01 using nginx
    solvers:
    - http01:
        ingress:
          ingressClassName: nginx
EOF

Then, you can create an ingress to expose 'my-service:80' on 'https://my-service.example.com' with:

$ microk8s enable ingress
$ microk8s kubectl create ingress my-ingress \
    --annotation cert-manager.io/issuer=letsencrypt \
    --rule 'my-service.example.com/*=my-service:80,tls=my-service-tls'
```

Comprobamos de nuevo que todo esté habilitado

```bash
microk8s status --wait-ready
```

### Configurar el almacenamiento persistente

Creamos un `PersistentVolumeClaim` (**_PVC_**) pra nuestro **Nexus3**.Y aprovechamos para crea el `namespace` que lo contendrá

- Archivo `nexus3-namespace-pvc.yaml`

  ```bash
    vi nexus3-namespace-pvc.yaml
  ```

  Contenido

```Yaml
apiVersion: v1
kind: Namespace
metadata:
  name: nexus3
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nexus3-pvc
  namespace: nexus3
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 35Gi
  storageClassName: microk8s-hostpath
```

- Aplicar el **_PVC_**

  `microk8s kubectl apply -f nexus3-namespace-pvc.yaml`

  - **apply -f**: Aplica la configuración desde un archivo

  - **accessModes=ReadWriteOnce**: El volumen será accesible desde un solo nodo

  - **resources.requests.storage=35Gi**: Reserva 35GB de almacenamiento

## Instalación de nexus3 con Helm

Añadir el repositorio **_Helm_** de **nexus3** , usaremos la versión integrada en **MicroK8s** de `helm` de `microk8s helm3`

```Bash
microk8s helm3 repo add stevehipwell https://stevehipwell.github.io/helm-charts/
microk8s helm3 repo update
```

Establecemos el password que se asignará mediante la variable de entorno export `NEXUS3_ADMIN_PASSWORD`

```Bash
export NEXUS3_ADMIN_PASSWORD=<TU_PASSWORD>
```

Y lo instalamos con las siguientes propiedades

```Yaml
replicaCount: 1

persistence:
  enabled: true
  existingClaim: nexus3-pvc

  accessMode: ReadWriteOnce

resources:
  requests:
    cpu: 250m
    memory: 1Gi
  limits:
    cpu: 500m
    memory: 2Gi

service:
  type: ClusterIP
  port: 8081

affinity: {}
tolerations: []
nodeSelector: {}

nexus:
  adminPassword: "${NEXUS3_ADMIN_PASSWORD}"   # Establecer el password definido en la variable de entorno

livenessProbe:
  enabled: true
readinessProbe:
  enabled: true

nexusProxy:
  enabled: false

# Namespace
namespaceOverride: nexus3
```

- Instala nexus3

```Bash
microk8s helm3 install nexus3 stevehipwell/nexus3 -f nexus3-chart-values.yaml
  ```

---

## Configurar el Ingress

El Ingress gestiona el acceso externo

### Configurar Cert-Manager

Cert-Manager automatiza la solicitud y renovación del certificado HTTPS.

Crea el archivo `letsencrypt-clusterissuer.yaml`

```bash
  vi letsencrypt-clusterissuer.yaml
```

apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: letsencrypt
spec:
  acme:
    # You must replace this email address with your own.
    # Let's Encrypt will use this to contact you about expiring
    # certificates, and issues related to your account.
    email: me@example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      # Secret resource that will be used to store the account's private key.
      name: letsencrypt-account-key
    # Add a single challenge solver, HTTP01 using nginx
    solvers:
    - http01:
        ingress:
          ingressClassName: nginx

apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: letsencrypt
spec:
  acme:
    # You must replace this email address with your own.
    # Let's Encrypt will use this to contact you about expiring
    # certificates, and issues related to your account.
    email: me@example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      # Secret resource that will be used to store the account's private key.
      name: letsencrypt-account-key
    # Add a single challenge solver, HTTP01 using nginx
    solvers:
    - http01:
        ingress:
          ingressClassName: nginx

Contenido

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt
spec:
  acme:
    email: alledova@gmail.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-account-key
    solvers:
      - http01:
          ingress:
            ingressClassName: nginx
```

Aplica la configuración:

```bash
 microk8s kubectl apply -f letsencrypt-clusterissuer.yaml
```

---

## Verificación

Comprueba los pods y recursos

```bash
  microk8s kubectl get all -n nexus3
```

Accede a nexus3:

- URL: `https://nexus3.moradores.es`.

- Obtén la contraseña inicial:

   ```Bash
   microk8s kubectl exec --namespace nexus3 -it svc/nexus3 -- cat /run/secrets/chart-admin-password
   ```

Ahora tu nexus3 estará completamente configurado con HTTPS y almacenamiento persistente.

---

1. Get your 'admin' user password by running:
  kubectl exec --namespace nexus3 -it svc/nexus3 -c nexus3 -- /bin/cat /run/secrets/additional/chart-admin-password && echo
2. Visit http://nexus3.moradores.es

3. Login with the password from step 1 and the username: admin
4. Configure security realm and authorization strategy
5. Use nexus3 Configuration as Code by specifying configScripts in your values.yaml file, see documentation: http://nexus3.moradores.es/configuration-as-code and examples: https://github.com/nexus3ci/configuration-as-code-plugin/tree/master/demos

Crea el archivo `nexus3_helm-ingress.yaml`:

```bash
  vi nexus3_helm-ingress.yaml
```

Contenido:

```yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: nexus3-ingress
     namespace: nexus3
     annotations:
       cert-manager.io/cluster-issuer: "letsencrypt-prod"
       nginx.ingress.kubernetes.io/rewrite-target: /
   spec:
     rules:
       - host: nexus3.moradores.es
         http:
           paths:
             - path: /
               pathType: Prefix
               backend:
                 service:
                   name: nexus3
                   port:
                     number: 8081
     tls:
       - hosts:
           - nexus3.moradores.es
         secretName: letsencrypt-account-key
```

Aplica la configuración:

```bash
   microk8s kubectl apply -f nexus3_helm-ingress.yaml
```


microk8s kubectl create ingress nexus3-ingress \
  --namespace nexus3 \
  --annotation cert-manager.io/cluster-issuer=letsencrypt \
  --rule 'nexus3.moradores.es/*=nexus3:8081,tls=nexus3-tls'

  

microk8s kubectl get svc -A | grep ingress

Gh123@32Fpq=H2o-