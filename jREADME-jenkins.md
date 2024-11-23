# Jenkins Local

## Introducción

Este proyecto consistente en montar un servicio [Jenkins](hrrps://jenkins.io) como parte de una infraestructura de laboratorio **CI/CD**.

Partimos de un servidor local con [Ubuntu 24.04LTS server](https://ubuntu.com/download/server) con [MicroK8s](https://microk8s.io/).

Este servidor conecta a Internet mediante un router local que dispone dispone de IP fija.

También disponemos de un servicio **DNS** alojado en [AWS](https://aws.amazon,es) para el dominio **_moradores.es_**

## Servicio Jenkins

El primer hito es tener un servicio **Jenkins** corriendo en el nodo **MicroK8s** con un volumen persistente de 8GB.

Para ello instalaremos el [Helm chart Jenkins](https://artifacthub.io/packages/helm/jenkinsci/jenkins) en el nodo.

Debe se accesible mediante HTTPS desde Internet. Usaremos un certificado [Let's encrypty](https://letsencrypt.org/es/). El _addon_  **Cert-Manager** de **MicroK8s** solicitará, desplegará y renovará por nosotros este certificado.

## Requisitos previos

### Configuración de DNS

Crear el registro **registro A** `jenkins.moradores.es` que apunte a la IP pública del router en el servicio **Route 53** de **AWS**

- **Host**: `jenkins.moradores.es`
- **Tipo**: A
- **Dirección IP**: IP pública del router

Podemos verifica que el registro funciona, una vez creado, con la utilidad `dig` que consulta registros **DNS**

`dig jenkins.moradores.es`

Ejemplo de repuesta del comando anterior

```Text
jenkins.moradores.es.   300     IN      A       185.221.8.108

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
  microk8s enable dns
  microk8s enable ingress
  microk8s enable hostpath-storage
  microk8s enable helm3
  microk8s enable cert-manager
```

- **dns**: Activa un servicio DNS interno

- **ingress**: Habilita controladores para gestionar accesos HTTP/HTTPS

- **hostpath-storage**: Proporciona volúmenes persistentes

- **helm3**: Permite usar Helm para instalar Jenkins

- **cert-manager**: Automatiza la gestión de certificados

Comprobamos de nuevo que todo esté habilitado

```bash
  microk8s status --wait-ready
```

### Configurar el almacenamiento persistente

Creamos un `PersistentVolumeClaim` (**_PVC_**) pra nuestro **Jenkins**.Y aprovechamos para crea el `namespace` que lo contendrá

- Archivo `jenkins-namespace-and-pvc.yaml`

  ```bash
    vi jenkins-namespace-and-pvc.yaml
  ```

  Contenido

  ```yaml
  apiVersion: v1
  kind: Namespace
  metadata:
    name: jenkins
  ---
  apiVersion: v1
  kind: PersistentVolumeClaim
  metadata:
    name: jenkins-pvc
    namespace: jenkins
  spec:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 8Gi
    storageClassName: microk8s-hostpath
  ```

- Aplicar el **_PVC_**

  ```bash
    microk8s kubectl apply -f jenkins-pvc.yaml
  ```

  - **apply -f**: Aplica la configuración desde un archivo

  - **accessModes=ReadWriteOnce**: El volumen será accesible desde un solo nodo

  - **resources.requests.storage=8Gi**: Reserva 8GB de almacenamiento

## Instalación de Jenkins con Helm

Añadir el repositorio **_Helm_** de **Jenkins** , usaremos la versión integrada en **MicroK8s** de `helm` de `microk8s helm`

```bash
  helm repo add jenkins https://charts.jenkins.io
  helm repo update
```

2. Instala Jenkins:
   ```bash
   helm install jenkins jenkins/jenkins \
     --namespace jenkins --create-namespace \
     --set controller.serviceType=ClusterIP \
     --set controller.ingress.enabled=true \
     --set controller.ingress.hostName=jenkins.almidom.es \
     --set persistence.existingClaim=jenkins-pvc \
     --set persistence.storageClass=manual \
     --set persistence.size=8Gi
   ```
   - **install jenkins**: Nombre del release y del chart.
   - **--namespace=jenkins**: Crea el espacio de nombres `jenkins`.
   - **--set**: Configura parámetros específicos:
     - **controller.serviceType=ClusterIP**: Expone el servicio internamente.
     - **controller.ingress.enabled=true**: Activa el uso de Ingress.
     - **controller.ingress.hostName=jenkins.almidom.es**: Define el dominio.
     - **persistence.existingClaim=jenkins-pvc**: Usa el volumen creado.

---

### **6. Configurar el Ingress**
El Ingress gestiona el acceso externo y la solicitud del certificado HTTPS.

1. Crea el archivo `jenkins-ingress.yaml`:
   ```bash
   nano jenkins-ingress.yaml
   ```
   Contenido:
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: jenkins-ingress
     namespace: jenkins
     annotations:
       cert-manager.io/cluster-issuer: "letsencrypt-prod"
       nginx.ingress.kubernetes.io/rewrite-target: /
   spec:
     rules:
       - host: jenkins.almidom.es
         http:
           paths:
             - path: /
               pathType: Prefix
               backend:
                 service:
                   name: jenkins
                   port:
                     number: 8080
     tls:
       - hosts:
           - jenkins.almidom.es
         secretName: jenkins-tls
   ```

2. Aplica la configuración:
   ```bash
   microk8s kubectl apply -f jenkins-ingress.yaml
   ```

---

### **7. Configurar Cert-Manager**
Cert-Manager automatiza la solicitud y renovación del certificado HTTPS.

1. Crea el archivo `letsencrypt-issuer.yaml`:
   ```bash
   nano letsencrypt-issuer.yaml
   ```
   Contenido:
   ```yaml
   apiVersion: cert-manager.io/v1
   kind: ClusterIssuer
   metadata:
     name: letsencrypt-prod
   spec:
     acme:
       server: https://acme-v02.api.letsencrypt.org/directory
       email: tuemail@dominio.com
       privateKeySecretRef:
         name: letsencrypt-prod
       solvers:
         - http01:
             ingress:
               class: nginx
   ```

2. Aplica la configuración:
   ```bash
   microk8s kubectl apply -f letsencrypt-issuer.yaml
   ```

---

### **8. Verificación**
1. Comprueba los pods y recursos:
   ```bash
   microk8s kubectl get all -n jenkins
   ```

2. Accede a Jenkins:
   - URL: `https://jenkins.almidom.es`.

3. Obtén la contraseña inicial:
   ```bash
   microk8s kubectl exec --namespace jenkins -it svc/jenkins -- cat /run/secrets/chart-admin-password
   ```

Ahora tu Jenkins estará completamente configurado con HTTPS y almacenamiento persistente.

