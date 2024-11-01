# CI/CD Jenkins - GithHub Actions

Para el seguimiento de esta tema  será necesario disponer de una cuenta personal en **Github**. Si no dispones aún de una puedes crearla gratuitamente en [https://github.com/]

Añade a tu cuenta personal de **GitHub** un _Fork_ del repositorio [https://github.com/spring-projects/spring-petclinic] (público). Será nuestra aplicación de ejemplo para abordar los procesos _CI/CD_

También será necesario instalar un servidor **Jenkins**. El método que emplearemos será un _deployment_ en un nodo local de **Kubernetes** que use un _persistentVolumeClaim_ para la persistencia de datos, al cual se le definirá un _service_ de tipo _clusterIP_ para acceder a la consola de **Jenkins**. La instalación del servicio **Jenkins** se abordará al inicio del tema

Para la instalación del nodo local **Kubernetes** se recomienda instalar **Microk8s**. En **Ubuntu 24.04LTS**, nuestro S.O. de referencia, la instalación y comprobación del estado del nodo se realiza con unos pocos pasos

Enlaces:

- Jenkins [https://jenkins.io]
- GitHub [https://github.com]
- Visual Estudio Code [https://code.visualstudio.com]
- MikroK8s [https://microk8s.io]

## Objetivos

- [x] Instalación de **MicroK8s** sobre **Ubuntu 24.04 LTS**

- [x] Desplegar un servicio **Jenkins** con persistencia de datos accesible mediante **_service ClusterIP_**

- [x] Crear un proceso CI/CD del un _Fork_ del proyecto [https://github.com/spring-projects/spring-petclinic] que incluya

  - [x] Construcción (Maven Build)
  - [x] Test Unitarios (Maven Test)
  - [x] Publicación (Publish in Nexus)
  - [x] Construcción imagen de contenedor (Docker Build)
  - [x] Publicación de la imagen de contenedor (Docker Push)
  - [x] Despliegue de un contenedor de la aplicación (Kubernetes Deployment)
  - [] Test de validación
  - [] Promoción de entorno (Development -> Production)

## Configuración Ubuntu 24.04 LTS

Configuración e instalación de las utilidades

### oh-my-bash

`oh-my-bash`, es una extensión al **shell Bash**, resulta de utilidad disponer de esta extensión cuando _trasteamos_ con **Git**, `oh-my-zsh` si de prefiere el **shell Zsh**

Instalación

```Bash
sudo apt install vim curl git terminator fonts-powerline
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)"
```

Edita `~/.bashrc`, con **vim** en el ejemplo, para actualizar el valor de `OSH_THEME` por el tema deseado, línea:

```Bash
vi ~/.bashrc
```

```Text
OSH_THEME="powerline"
```

`source ~/.bashrc` Para aplicar los cambios

### MS Code

Pudiendo seguir el _tema_, en cualquier otro _IDE_ o editor, MS Code, es una opción ligera y versátil.

Descargar de [https://code.visualstudio.com] la versión `.dev` e instalar con `apt`

```Bash
apt install ./<archivo_code_descargado>.dev
```

Una vez instalado lanzar el _IDE_, por ejemplo ejecutado `code`

Es recomendable instalar las siguientes extensiones, que facilitan trabajar con repositorios _Git_

- Git Graph

- GitLens - Git supercharged

Podemos hacerlo pulsando la rueda dentada de la barra de menu de la izquierda y seleccionado _extensiones_ ( Crtl + Mayús + X ), y buscar las extensiones en el Marketplace

### microk8s.ioc

Como el sistema operativo de los equipos facilitados para la realización del _tema_ ha sido **Ubuntu 24.04 LTS**, la plataforma **Kubernetes** elegida ha sido [MicroK8s](https://microk8s.io), por su simplificación a la hora de la instalación, versatilidad y cumplimiento de los estándares **Kubernetes**, en este S.O.

Instalación, configuración inicial, y comandos de gestión

```Bash
sudo snap install microk8s --classic

sudo usermod -a -G microk8s $USER

sudo chown -f -R $USER ~/.kube

su - $USER

microk8s status --wait-ready

microk8s enable dashboard

microk8s enable dns

microk8s enable hostpath-storage

microk8s enable registry

microk8s kubectl get all --all-namespaces
```

Añadir alias `kubectl` en `~/.bashrc`

`alias kubectl="microk8s kubectl"`

Comandos de gestión del nodo

```Bash
microk8s reset
microk8s stop
```

## Instalación y configuración de Jenkins en MicroK8s

Una vez tenemos el SO preparado procedemos a la instalación de **Jenkins** sobre **MicroK8s**

Configura **Git** si aun lo has hecho

```Bash
git config --global user.name "Nombre del usuario"
git config --global user.email "mail@dominio.net"
git config --global http.sslverify false
git config --global credential.helper store
```

Clona este repositorio a tu equipo `git clone https://github.com/antoniollv/bc-hybrid-cloud-4.git`

Lanza MS Code en el directorio del repositorio

```Bash
cd bc-hybrid-cloud-4
code .
```

El repositorio en su rama `main` a parte del presente documento, `README.md`, contiene los distintos **YAMLs** que iremos adaptando y aplicando para desplegar la infraestructura que emplearemos en nuestro proceso CI/CD

EL primer paso es desplegar nuestra herramienta de automatización, **Jenkins**, que necesitará persistencia de datos para no perder los avances

### Configurar PersistentVolume (PV) en MicroK8s

- Activar el complemento `hostpath-storage` en **MicroK8s**

  `kubectl get pods -n kube-system | grep 'hostpath-provisioner'`
  
  Debe mostrar un pod `hostpath-provisioner` en el espacio de nombres `kube-system`, lo que indica que el complemento está activo

  EN canso contrario activar con el comando `microk8s enable hostpath-storage`

- Crear un PersistentVolumeClaim (PVC)

  En **MicroK8s**, no es necesario definir un **PV** manualmente porque el complemento `hostpath-storage` crea automáticamente un **PV** cuando se hace una solicitud de `PersistentVolumeClaim`

  Para crear un `PersistentVolumeClaim` utilizaremos el archivo **YAML** `jenkins-pvc.yaml`

```Yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jenkins-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi  # Aquí defines la cantidad de almacenamiento que tendrá el volumen, no te quedes corto
  storageClassName: microk8s-hostpath
```

  Aplicamos y verificamos

```Bash
kubectl apply -f jenkins-pvc.yaml
kubectl get pvc
```

### Jenkins Deployment

La forma más simple de tener un `Deployment` **Jenkins** en nuestro nodo **Microk8s** sería ejecutando

`kubectl create deployment jenkins --image jenkins/jenkins`

Pero queremos asignarle el **PVC** creado anteriormente, para ello se realiza una _ejecución seca_, se redirige la salida a archivo y modificamos el archivo ***YAML*** resultante, para agregar el volumen.

`kubectl create deployment jenkins --image=jenkins/jenkins --dry-run=client -o yaml > jenkins-deployment.yaml`

Una vez editado `jenkins-deployment.yaml` lo dejamos de este modo

**_jenkins-deployment_**

```Yaml
kind: Deployment
metadata:
  labels:
    app: jenkins
  name: jenkins
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jenkins
  template:
    metadata:
      labels:
        app: jenkins
    spec:
      containers:
      - image: jenkins/jenkins
        name: jenkins
        volumeMounts:
        - mountPath: /var/jenkins_home
          name: storage
      volumes:
      - name: storage
        persistentVolumeClaim:
          claimName: jenkins-pvc
```

Lo encontraras ya modificado en el repositorio

Aplicamos el archivo y comprobamos que tanto el pod como el deployment están disponibles

```Bash
kubectl apply -f jenkins-deployment.yaml
kubectl get all
```

Por último exponemos el servicio para acceder a **Jenkins**

`kubectl expose deployment jenkins --port 8080 --target-port 8080 --selector app=jenkins --type ClusterIP --name jenkins`

Podemos ver la  ip de acceso a nuestro Jenkins consultando los `services`

`kubectl get services | grep jenkins`

Url de acceso a **Jenkins** [http://IP_SERVICE:8080)]

---

## Configuración y primero pasos con Jenkins

Para desbloquear **Jenkins** debemos obtener la contraseña de inicio, para ello seguiremos las indicaciones mostradas en la **URL** del **Jenkins**.

Bastará con realizar `cat` sobre el archivo indicado en el `pod` de **Jenkins**

```Bash
kubectl get pods
kubectl exec -it <JENKINS_POD_NAME> -- cat /var/jenkins_home/secrets/initialAdminPassword
```

Para finalizar la instalación seguimos los pasos del asistente de configuración.

[https://www.jenkins.io/doc/book/installing/kubernetes/#setup-wizard](https://www.jenkins.io/doc/book/installing/kubernetes/#setup-wizard)

### Agregar plugins

Podemos completar la instalación agregando algunos plugins más que emplearemos en las siguientes secciones

- En _Panel de Control_ -> _Administrar Jenkins_, Opción **Plugins**

- En _Availabe plugins_, Buscar y seleccionar:

  - Kubernetes plugin
  - Azure Key Vault Plugin

Reiniciamos Jenkins  activando el check de reinicio mostrado durante la instalación de los _plugins_

### Configurar Cloud y Pod Templates

Configurar **Cloud**

- En _Panel de Control_ -> _Administrar Jenkins_, **New cloud**
  
  - Name: kubernetes
  - WebSocket: `true`
  - Jenkins URL: Url del servicio Jenkins, Ejemplo: http:10.152.183.244:8080
  - Resto de valores por defecto o en blanco

  **Save** para guardar los cambios

Configurar **Pod Templates**

- En _Panel de Control_ -> _Administrar Jenkins_ -> _kubernetes_ -> _Pod Templates_, **Add a pod template**

  - Name: pod-default
  - Labels: pod-default
  - Usage: Utilizar este nodo tanto como sea posible
  - Name of the container that will run the Jenkins agent: jnlp
  - Add Container
    - Name: jnlp
    - Docker image: jenkins/inbound-agent
    - Working directory: /home/jenkins/agent
    - Command to run: _en blanco, borrar sleep_
    - Arguments to pass to the command: ${computer.jnlpmac} ${computer.name}
  - Add Container
    - Name: maven
    - Docker image: maven
    - Working directory: /home/jenkins/agent
  - Resto de valores por defecto o en blanco

  **Save** para guardar los cambios

## Primera tarea en Jenkins

Procedemos a crear una tarea para probar la configuración de la **Cloud Kubernetes** y la **Pod template**

- En _Panel de Control_ -> _+ Nueva Tarea_
  
  - Enter an item name: test
  - Opción, **Pipeline**
  - **OK**
    - Descripción: Test Job Kubernetes
    - Pipeline -> Definition -> Pipeline script -> Script, Seleccionar _Hello Work_ en el desplegable _try sample Pipeline_
      Actualizar el script a

      ```Groovy
      pipeline {
        agent { label 'pod-default' }
        stages {
          stage('Hello') {
            steps {
              echo "Hello World from ${JENKINS_AGENT_NAME}"
            }
          }
        }
      }
      ```

    - **SAVE**
  - En _Panel de Control_ -> _test_, **> Construir ahora**

Espera a la finalización del trabajo

Si pulsas sobre el número, #1 Veras la información de la construcción

En el menu del la izquierda en **Console Output** tienes el registro del trabajo, se puede seguir mientras se ejecuta la tarea

## Configurar tarea de ciclo de vida de una aplicación en Jenkins

### Requisito previos

Revisemos los requisito previos:

- Cuenta en GitHub [hrrps://github.com]

- Realizar **Folk** en cuenta personal del repositorio [https://github.com/spring-projects/spring-petclinic](https://github.com/spring-projects/spring-petclinic), de momento déjalo como público

- En Jenkins configurar el rate limit de GitHUb
  - En _Panel de Control_ -> _Administrar Jenkins, _System_ en GitHub API usage , establecer la opción _GitHub API usage rate limiting strategy_ a **Throttle at/near rate limit**. **Save** para guardar los cambios

- Abrir nuestro _Fork_ del repositorio `spring-petclinic` en **MS Code**

  Copia la URL de tu proyecto en **GitHub** al portapapeles y pégala en una interprete de comandos añadiendo `git clone`

  **_¡Cuidado!_** no copies de aquí debes adaptar la **URL** a tu usuario de **GitHub**

  ```Bash
  git clone https://github.com/<Tu_usuario_GitHub>/bc-hybrid-cloud-4.git
  cd bc-hybrid-cloud-4.git
  code .
  ```

- En este punto hablemos sobre **Git**, conceptos básicos , algunos comandos y algunos flujos que se pueden adoptar

- Sigamos creando la _rama_ `develop` a nuestro Fork de `spring-petclinic`

  ```Bash
  # Sacar rama local a partir de la actual
  git checkout -b develop

  # Sincronizar por primera vez la nueva rama local con remoto
  git push --set-upstream origin develop

  ```

- Crear archivo Jenkinsfile en el directorio raíz del proyecto

  En Jenkins definimos el trabajo a realizar, **_Jenkins Pipeline _** en un archivo usualmente llamado `Jenkinsfile`
  
  Copia, de este repositorio, el archivo `Jenkinsfile.inicial` a tu repositorio `spring-petclinic` cambiando el nombre a `Jenkinsfile`. Recuerda estamos en rama `develop`

  ```Groovy
  #!/usr/bin/env groovy
  pipeline {
      agent { label 'pod-default' }
      stages {
          stage('Check Environment') {
              steps {
                  sh 'java -version'
                  container('maven') {
                      sh '''
                          java -version
                          mvn -version
                          pwd
                      '''
                  }
              }
          }
      }
  }
  ```

  Sube los cambios

  ```Bash
  git add Jenkinsfile
  git commit -m "Add Jenkins Pipeline"
  git push
  ```

- Veamos un poco de teoría sobre **Jenkins Pipeline** antes de continuar

### Construcción de la Jenkins Pipeline - flujo CI/CD

Una vez cumplidos con los requisitos previos vanos a crear el proyecto, tarea, en **Jenkins** con el que realizaremos la prueba de concepto de una **Pipeline CI/CD**

- En _Panel de Control_ -> _+ Nueva Tarea_
  
  - Enter an item name: spring-petclinic
  - Opción, **Multibranch Pipeline**
  - **OK**
    - Display Name: Spring Petclinic
    - Descripción: Spring Petclinic Sample Application
    - Branch Sources, GitHub -> _Repository HTTPS URL_ **La URL de nuestro repositorio en GitHub**

- **Save**

---

Test unitarios

Aseguremos que el plugin JUnit este instalado

---

export POSTGRES_PASSWORD="Pon aquí tu password"
export POSTGRES_PASSWORD="HJR649-gd123@mj"
kubectl get all
kubectl exec -it <nombre-del-pod-de-postgresql> -- psql -U artifactory -d artifactorydb
kubectl exec -it postgresql-5d558c74bb-h7tqg -- psql -U artifactory -d artifactorydb

---

az ad sp create-for-rbac --name "azure-sp" \
  --role "Key Vault Secrets User" \
  --scopes "/subscriptions/dabd2ed3-f9cd-496c-b6e3-42d3e0a7e0a5/resourceGroups/bootcamp/providers/Microsoft.KeyVault/vaults/default01"

---
Ruta almacenamiento
/var/snap/microk8s/common/default-storage

---

Crear deployment nexus

```Bash
kubectl apply -f nexus-pvc.yaml
kubectl apply -f nexus-deployment.yaml
```

Obtener el Password del administrador

```BAsh
kubectl get pods
kubectl exec -it <nexus-pod-name> -- cat /nexus-data/admin.password
```

---

### Agregar Container Template Kaniko y Kubectl

- En _Panel de Control_ -> _Administrar Jenkins_ -> _kubernetes_ -> _Pod Templates_, **pod-default**

  - Add Container
    - Name: kaniko
    - Docker image: gcr.io/kaniko-project/executor:latest
    - Working directory: /home/jenkins/agent
    - Command to run: cat
    - Arguments to pass to the command: _En blanco_
    - Allocate pseudo-TTY: true
  - Add Container
    - Name: kubectl
    - Docker image: bitnami/kubectl:latest
    - Working directory: /home/jenkins/agent
    - Command to run: cat
    - Arguments to pass to the command: _En blanco_
    - Allocate pseudo-TTY: true
  
---

## Configuración para ejecutar kubectl en contenedor

### Install kubectl binary with curl on Linux

[https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/]

Download the latest release with the command

```Bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
```

Download the kubectl checksum file

```Bash
 curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
```

Validate the kubectl binary against the checksum file

```Bash
 echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
```

If valid, the output is:

`kubectl: OK`

If the check fails, sha256 exits with nonzero status and prints output similar to:

```Txt
kubectl: FAILED
sha256sum: WARNING: 1 computed checksum did NOT match
```

Install kubectl

```Bash
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

Note:

If you do not have root access on the target system, you can still install kubectl to the ~/.local/bin directory:

```Bash
chmod +x kubectl
mkdir -p ~/.local/bin
mv ./kubectl ~/.local/bin/kubectl
# and then append (or prepend) ~/.local/bin to $PATH
```

Test to ensure the version you installed is up-to-date:

```Bash
kubectl version --client
```

### Instalación Jenkins Pipeline

```Groovy
sh '''
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl
  mkdir -p ~/.local/bin
  mv ./kubectl ~/.local/bin/kubectl
  kubectl version --client
  kubectl get all
'''
```

kubectl create deployment petclinic --image 10.152.183.54:8082/repository/docker/spring-petclinic:latest
kubectl expose deployment petclinic --port 8080 --target-port 8888 --selector app=petclinic --type ClusterIP --name petclinic
---

## Resolviendo problemas de resolución de DNS en MicroK8s

La resolución DNS en MicroK8s se encarga de permitir que los servicios y pods dentro del clúster puedan resolverse mutuamente por nombre en lugar de direcciones IP.

Habilitar el DNS en MicroK8s `microk8s enable dns`. Con `microk8s status` comprobamos el estado

Algunas posibles causas y soluciones si falla la resolución DNS

1. **Verificar el Pod de CoreDNS**: En MicroK8s, el servicio DNS lo proporciona CoreDNS. Verificar que el pod de CoreDNS esté corriendo:

   ```Bash
   microk8s kubectl get pods -n kube-system
   ```

   El pod debe estar en estado `Running`. Si muestra errores, revisar los logs:

   ```Bash
   microk8s kubectl logs -n kube-system <nombre_del_pod_coredns>
   ```

2. **Revisar Configuración del Servicio DNS**: Verifica que el servicio DNS esté activo y que tenga una IP ClusterIP asociada:

   ```Bash
   microk8s kubectl get svc -n kube-system
   ```

   Busca un servicio llamado `kube-dns`. Debe tener una IP y el tipo de servicio debe ser `ClusterIP`.

3. **Probar Resolución DNS Interna**: Dentro del clúster, se puede ejecutar un contenedor de prueba y usar herramientas como `nslookup` o `dig` para verificar la resolución de nombres. Ejemplo:

   ```Bash
   microk8s kubectl run -i --tty busybox --image=busybox --restart=Never -- sh
   ```

   Una vez dentro del contenedor:

   ```Bash
   nslookup <nombre_del_servicio>.<namespace>.svc.cluster.local
   ```

4. **Reiniciar CoreDNS**: Si se detecta algún problema, reiniciar el pod de CoreDNS. Eliminar el pod, y Kubernetes lo recrea automáticamente:

   ```Bash
   microk8s kubectl delete pod -n kube-system <nombre_del_pod_coredns>
   ```
