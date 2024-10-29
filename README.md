# CI/CD Jenkins - GithHub Actions

Para el seguimiento de esta tema  será necesario disponer de una cuenta personal en **Github**. Si no dispones aún de una puedes crearla gratuitamente en [https://github.com/]

Añade a tu cuenta personal de **GitHub** un _Fork_ del repositorio [https://github.com/spring-projects/spring-petclinic]. Será nuestra aplicación de ejemplo para abordar los procesos _CI/CD_

También será necesario instalar un servidor **Jenkins**. El método que emplearemos será un _deployment_ en un nodo local de **Kubernetes** que use un _persistentVolumeClaim_ para la persistencia de datos, al cual se le definirá un _service_ de tipo _clusterIP_ para acceder a la consola de **Jenkins**. La instalación del servicio **Jenkins** se abordará al inicio del tema

Para la instalación del nodo local **Kubernetes** se recomienda instalar **Microk8s**. En **Ubuntu 24.04LTS**, nuestro S.O. de referencia la instalación y comprobación del estado del nodo se realiza con unos pocos pasos

Enlaces:

- Jenkins [https://jenkins.io]
- GitHub [https://github.com]
- Visual Estudio Code [https://code.visualstudio.com]
- MikroK8s [https://microk8s.io]

## Configuración Ubuntu 24.04 LTS

Configuración e instalación de las utilidades

### oh-my-bash

Resulta de utilidad disponer de esta extensión al Shell Bash para trastear con Git, o oh-my-zsh si de prefiere el Shell Zsh

Instalación 

```Bash
sudo apt install vim curl git terminator fonts-powerline
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)"
```

Edita `~/.bashrc` para actualizar el valor de `OSH_THEME` por el tema deseado, línea:

```Bash
vi ~/.bashrc
```

```Text
OSH_THEME="powerline"
```

#### MS Code

Descargar del enlace la versión `.dev` e instalar con `apt`

```Bash
apt install ./<archivo_code_descargado>.dev
```

### microk8s.ioc

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

#### Configurar PersistentVolume (PV) en MicroK8s

- Activar el complemento `hostpath-storage` en **MicroK8s**

  `kubectl get pods -n kube-system | grep 'hostpath-provisioner'`
  
  Debe mostrar un pod `hostpath-provisioner` en el espacio de nombres `kube-system`, lo que indica que el complemento está activo.

  EN canso contrario activar con el comando

  `microk8s enable hostpath-storage`

- Crear un PersistentVolumeClaim (PVC)

  En **MicroK8s**, no es necesario definir un **PV** manualmente porque el complemento `hostpath-storage` crea automáticamente un **PV** cuando se hace una solicitud de `PersistentVolumeClaim`

  Para crear un `PersistentVolumeClaim` creamos un archivo **YAML** con su definición por ejemplo `jenkins-pvc.yaml`

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
      storage: 5Gi  # Define la cantidad de almacenamiento que necesitas
  storageClassName: microk8s-hostpath
```

  Aplicamos y verificamos

```Bash
kubectl apply -f jenkins-pvc.yaml
kubectl get pvc
```

## Jenkins Deployment

La forma más simple de tener un `Deployment` **Jenkins** en nuestro nodo **Microk8s** sería ejecutando

`mkctl create deployment jenkins --image jenkins/jenkins`

Pero queremos asignarle el **PVC** creado anteriormente para ello realizamos una _ejecución seca_ y modificamos el archivo *YAML* resultante, para agregar el volumen.

`kubectl create deployment jenkins --image=jenkins/jenkins --dry-run=client -o yaml > jenkins-deployment.yaml`

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

Para desbloquear **Jenkins** debemos obtener la contraseña de inicio, para ellon seguiremos las indicaciones mostradas en la **URL** del **Jenkins**.

Bastará con realizar `cat` sobre el archivo indicado en el `pod` de **Jenkins**

```Bash
kubectl get pods
kubectl exec -it <JENKINS_POD_NAME> -- cat /var/jenkins_home/secrets/initialAdminPassword
```

Para finalizar la instalación seguimos los pasos del asistente de configuración.

[https://www.jenkins.io/doc/book/installing/kubernetes/#setup-wizard](https://www.jenkins.io/doc/book/installing/kubernetes/#setup-wizard)

### Agregar plugins

- En _Panel de Control_ -> _Administrar Jenkins_, Opción **Plugins**

- En _Availabe plugins_, Buscar y seleccionar:

  - Kubernetes plugin
  - Azure Key Vault Plugin

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

## Configurar tarea de ciclo de vida de una aplicación

Requisito previos:

- Cuenta en GitHub

- Realizar **Folk** en cuenta personal del repositorio [https://github.com/spring-projects/spring-petclinic](https://github.com/spring-projects/spring-petclinic)

- En Jenkins configurar el rate limit de GitHUb
  - En _Panel de Control_ -> _Administrar Jenkins, _System_ en GitHub API usage , establecer la opción _GitHub API usage rate limiting strategy_ a **Throttle at/near rate limit**. **Save** para guardar los cambios

- Abrir el proyecto en **MS Code**

- Teoría GIT

- Crear Rama develop

- Crear archivo Jenkinsfile en el directorio raíz del proyecto

- Teoría Jenkins Pipeline

Una vez cumplidos los requisitos previos Crearemos el proyecto, tarea, en Jenkins con el que realizaremos la prueba de concepto de una **Pipeline CI/CD**

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
