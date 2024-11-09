# CI/CD con Jenkins

Para el seguimiento de esta tema  será necesario disponer de una cuenta personal en **Github**. Si no dispones aún de una puedes crearla gratuitamente en [https://github.com/]

Añade a tu cuenta personal de **GitHub** un _Fork_ del repositorio [https://github.com/spring-projects/spring-petclinic] (en tu cuenta hazlo público). Será nuestra aplicación de ejemplo para abordar los procesos _CI/CD_

También será necesario un servidor **Jenkins**. Lo instalaremos al principio de este _tema_. El método que emplearemos será un _deployment_ en un nodo local de **Kubernetes** que use un _persistentVolumeClaim_ para la persistencia de datos, al cual se le definirá un _service_ de tipo _clusterIP_ para acceder a la consola de **Jenkins**

Para la instalación del nodo local **Kubernetes** se recomienda instalar **Microk8s**. En **Ubuntu 24.04LTS**, nuestro S.O. de referencia. La instalación y comprobación del estado del nodo se realiza con unos pocos pasos

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
  - [ ] Tests de validación
  - [ ] Promoción de entorno (Development -> Production)

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

Clona el presente repositorio, el repositorio de refernecia del _tema_ a tu equipo `git clone https://github.com/antoniollv/bc-hybrid-cloud-4.git`, para tener a tu disposición el código que iremos usando

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

Lo encontraras ya actualizado en el repositorio del _tema_

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

### Construcción de la Jenkins Pipeline - flujo CI/CD - Rama Develop

Una vez cumplidos con los requisitos previos vanos a crear el proyecto, tarea, en **Jenkins** con el que realizaremos la prueba de concepto de una **Pipeline CI/CD**

- En _Panel de Control_ -> _+ Nueva Tarea_
  
  - Enter an item name: spring-petclinic
  - Opción, **Multibranch Pipeline**
  - **OK**
    - Display Name: Spring Petclinic
    - Descripción: Spring Petclinic Sample Application
    - Branch Sources, GitHub -> _Repository HTTPS URL_ **La URL de nuestro repositorio en GitHub**

- **Save**

Una vez la tarea esté agregada al **Jenkins** este procederá  a examinar el repositorio y agregará todas aquellas ramas donde encuentre un archivo `Jenkinsfile`. A continuación ejecutara la tarea definida el `Jenkinsfile`.

Como en nuestro en nuestro repositorio en rama `develop` tenemos un `Jenkisfile` **Jenkins** proceder a ejecutar la tarea, la **_Jenkins Pipeline_**. Cada una de las ejecuciones es un trabajo, una construcción, _Build_, y van numeradas de forma secuencial

Si todo va bien veremos el trabajo concluido correctamente indicado con un _check verde_

Si examinamos el registro del trabajo, pulsando sobre el símbolo del _check verde_, veremos que este muestra las versión de **Java** instaladas en el contenedor `jnlp` (contenedor por defecto) y `maven`, en este último contenedor se muestra también la versión de **Maven** así como el directorio de trabajo (comando `pwd`).

Por el contrario si se produce algún error este irá indicado con una _aspa rojo_, pudiendo revisar el registro de igual forma, pulsando sobre el símbolo.

#### Agregar Stage de construcción

Empecemos ha hacer cosas interesante, no solo mostrar información de los contenedores que conforman nuestro agente de construcción, ese **_Pod de Kubernetes_** que definimos mediante un plantilla al configurar el **Jenkins**

Vamos a agregar una etapa de compilación a nuestro proyecto `spring-petclinic`.

Para ello en **Code** añadimos el siguiente código a nuestro `Jenkinsfile` justo a continuación de la `stage('Check Environment')`

```Groovy
stage('Build') {
    steps {
        container('maven') {
            println '01# Stage - Build'
            println '(develop y main):  Build a jar file.'
            sh './mvnw package -Dmaven.test.skip=true'
            archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
        }
    }
}
```

Para asegurar que no se cometen errores al insertar el código, puedes sustituir el archivo `Jenkinsfile` actual copiando el archivo `Jenkinfile.build` de este repositorio. Reemplaza el archivo no te limites a copiarlo

Una vez actualizado el archivo Jenkinsfile, subimos los cambios al repositorio.

  ```Bash
  git add Jenkinsfile
  git commit -m "Add Stage Build"
  git push
  ```

Y pulsamos sobre **_Construir ahora_** en la tarea Jenkins, podemos seguir la ejecución de la tarea en el registro pulsando sobre el símbolo de estado.

Esta vez tardará considerablemente más en terminar, ya que el proceso descarga, mediante **Maven**, todas las dependencias que necesita para su construcción.

Si al finalizar la tarea podemos leer en la ultima linea del registro **Finished: SUCCESS** es que todo ha ido bien

Habremos conseguido dos cosas:

- Hemos comprobado que nuestro proyecto compila
- Tendremos un archivo **Jar** con el código empaquetado de la aplicación listo para desplegar

#### Test unitarios

En esta sección añadiremos una etapa en la que se recopila la información obtenida de la ejecución de los test unitarios, aquellos que añaden los desarrolladores para comprobar el correcto funcionamiento de la aplicación

Ya estará instalado, al venir con los plugins sugerido en la configuración inicial de Jenkins, pero nos aseguremos que el plugin **JUnit** este instalado

- En _Panel de Control_ -> _Administrar Jenkins_, Opción **Plugins**

- En _Installed plugins_, Buscar:

  - JUnit Plugin

De no encontrarse instalado en - En _Availabe plugins_, lo buscamos, seleccionamos e instalamos

Esta vez no basta con agregar una nueva etapa al Jenkisfile debemos añadir la dependencia Junit al archivo pom.xml de repositorio

En _dependencies_

```xml
<dependency>
  <groupId>org.junit.jupiter</groupId>
  <artifactId>junit-jupiter</artifactId>
  <version>5.11.3</version>
  <scope>test</scope>
</dependency>
```

En _plugins_

```xml
<plugin>
  <groupId>org.apache.maven.plugins</groupId>
  <artifactId>maven-surefire-plugin</artifactId>
  <version>3.5.1</version>
  <configuration>
    <reportsDirectory>${project.build.directory}/surefire-reports</reportsDirectory>
  </configuration>
</plugin>
```

Y añadimos una nueva etapa, `stage('Unit Tests')`

```Groovy
stage('Unit Tests') {
    when {
        anyOf {
            branch 'main'
            branch 'develop'
        }
    }
    steps {
        container('maven') {
            println '03# Stage - Unit Tests'
            println '(develop y main): Launch unit tests.'
            sh '''
                mvn test
            '''
            junit '**/target/surefire-reports/*.xml'
        }
    }
}
```

Si reemplaza el archivo `Jenkinsfile` por el archivo `Jenkisfile.unittest` de este repositorio y lo examinas, veras que se han añadido un comentario a las condiciones de ejecución por ramas, para reducir los tiempos de ejecución de la _Pipeline_. Ya se desharán los cambios más adelante

Una vez subidos los cambios al repositorio en **GitHub** lanza una nueva construcción en **Jenkins**

Si la construcción es correcta, pulsa en el número de la construcción, veras los reportes de **JUnit**

#### Despliegue de un servicio Nexus en MicroK8s

Antes de abordar la siguiente etapa vamos a abordar el despliegue de un servicio **Nexus** en **MicroK8s**

**Nexus** proporciona un repositorios de artefactos **Maven** y de imágenes de contenedor. Utilizaremos este servicio para publicar los artefactos generado en nuestra **_Pipeline_**

En los archivos **YAMLs** proporcionados ya se encuentra la definición de los servicio

Crear deployment nexus

```Bash
kubectl apply -f nexus-pvc.yaml
kubectl apply -f nexus-deployment.yaml
```

Obtenemos la ip del servicio **Nexus**

```Bash
kubectl get services | grep "nexus-service"
```

Y accedemos al puerto http 8081

Url Nexus [http://IP_SERVICIO_NEXUS:80081]

Obtener el Password del administrador

```BAsh
kubectl get pods | grep "nexus"
kubectl exec -it <NEXUS_POD_NAME> -- cat /nexus-data/admin.password
```

Una vez hemos accedido a la interfaz de **Nexus**. Debemos realizar las siguientes acciones

- Completar el asistente de inicio de **Nexus**

  Ve a la esquina superior izquierda y pulsa sobre _Sing in_, Introduce el usuario _admin_ y el password obtenido anteriormente

  El asistente de cuatro pasos se iniciara, Botón _Next_

  Establecer un nuevo password al usuario _admin_, no lo compliques mucho, deberás recordarlo, Botón _Next_

  Selecciona _Enable anonymous access_, Botón _Next_ y Botón _Finish_

  ![Nexus Sign in](https://github.com/antoniollv/bc-hybrid-cloud-4/blob/main/imgs/nexus-sign_in.png "Nexus Sign in")

- Añadir repositorio **docker**

  En la barra superior selecciona la rueda dentada, en el menu vertical de la izquierda selecciona _Repository_ -> _Repositories_

  Pulsa sobre el botón _+ Create repository_, selecciona _Recipe_ **_docker (hosted)_**

  - Name: docker
  - Activar, check - HTTP: 8082
  - Activar, check - Allow anonymous docker pull ( Docker Bearer Token Realm required)

  Resto de opciones en blanco o por omisión

  Pulsar sobre el botón _Create repository_ al fina del formulario

  ![Nexus Docker repository](https://github.com/antoniollv/bc-hybrid-cloud-4/blob/main/imgs/nexus-docker_repository.png "Nexus Docker repository")

- Activar identificación _Docker Bearer Token Realm_
  
  En la barra superior selecciona la rueda dentada, en el menu vertical de la izquierda selecciona _Security_ -> _Realms_

  Desplazamos _Docker Bearer Token Realm_ de _Available_ a _Active_ y lo situamos en primera posición, Botón _Save_

  ![Nexus Docker Realm](https://github.com/antoniollv/bc-hybrid-cloud-4/blob/main/imgs/nexus-docker_realms.png "Nexus Docker Realm")

- Asignar rol administrador (nx-admin) al usuario anonymous

  En la barra superior selecciona la rueda dentada, en el menu vertical de la izquierda selecciona _Security_ -> _Users_

  Pulsa sobre _anonymous_

  En Roles deplazamos _nx-admin_ de _Available_ a _Granted_, Botón _Save_

  ![Nexus User anonymous](https://github.com/antoniollv/bc-hybrid-cloud-4/blob/main/imgs/nexus-user_anonymous.png "Nexus User anonymous")

- En el nodo **MicroK8s** permitir repositorios de imágenes inseguros

  En el siguiente enlace encontramos información de como establecer un registro de imágenes de contenedor local como _Insecure registry_ [https://microk8s.io/docs/registry-private] en **MicroK8s**

  Necesitaremos la IP del servicio **Nexus** `kubectl get services | grep "nexus-service"`.

  Crear directorio y fichero `hosts.toml`

  ```Bash
  sudo mkdir -p /var/snap/microk8s/current/args/certs.d/<IP_SERVICIO_NEXUS>:8082
  sudo touch /var/snap/microk8s/current/args/certs.d/<IP_SERVICIO_NEXUS>:8082/hosts.toml  
  ```

  Editamos el archivo host.toml `sudo vi touch /var/snap/microk8s/current/args/certs.d/<IP_SERVICIO_NEXUS>:8082/hosts.toml`

  Con el siguiente contenido

  ```Toml
  # /var/snap/microk8s/current/args/certs.d/<IP_SERVICIO_NEXUS>:8082/hosts.toml
  server = "<IP_SERVICIO_NEXUS>:8082"
 
  [host."http://<IP_SERVICIO_NEXUS>:8082"]
  capabilities = ["pull", "resolve"]
  ```

  Por último reiniciamos **MicroK8s**
  
  ```Bash
  microk8s stop
  microk8s start
  ```

> ¡Atención! Cabe destacar que estas acciones van en contra de la buenas practicas en materia de seguridad, se realizan aquí, de esta forma, en este momento, con el fin de no añadir aun más complejidad al _tema_

#### Stages de publicación en repositorio de artefactos, Maven y Docker

Una vez realizada la compilación y pasados los tests unitarios, y comprobado que disponemos de un servicio de repositorio de artefactos, el servicio **Nexus** que hemos montado y configurado en el apartado anterior. Procedemos a añadir a nuestro `Jenkinsfile` del proyecto `spring-petclinic` dos nuevas etapa de publicación de artefactos.

`Publish Artifact`, en esta etapa publicaremos en **Nexus** el archivo **JAVA** `spring-petclinic-3.3.0-SNAPSHOT.jar` fruto de la primera etapa de construcción. Añadir la etapa a Jenkinsfile de `spring-petclinic`

```Groovy
stage('Publish Artifact') {
    when {
        anyOf {
            branch 'main'
            branch 'develop'
        }
    }
    steps {
        container('maven') {
            println '04# Stage - Deploy Artifact'
            println '(develop y main): Deploy artifact to repository.'
            sh '''
                mvn -e deploy:deploy-file \
                    -Durl=http://nexus-service:8081/repository/maven-snapshots \
                    -DgroupId=local.moradores \
                    -DartifactId=spring-petclinic \
                    -Dversion=3.3.0-SNAPSHOT \
                    -Dpackaging=jar \
                    -Dfile=target/spring-petclinic-3.3.0-SNAPSHOT.jar
            '''
        }
    }
}
```

`Build & Publish Container Image` en esta etapa no solo nos limitaremos a publicar la imagen de contenedor, también necesitamos construirla, para ello necesitaremos un archivo _Dockerfile_. Añádelo al repositorio `spring-petclinic`

```Dockerfile
FROM eclipse-temurin:17-jdk-alpine AS builder
WORKDIR /app
ARG VERSION=3.3.0-SNAPSHOT.jar
COPY target/spring-petclinic-$VERSION app.jar
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
EXPOSE 8080
```

También necesitaremos  un contenedor capaz de construir imágenes de contenedor. Un contenedor **Kaniko** puede construir y publicar imágenes. Hay que añadir una nueva definición de contenedor a nuestra plantilla

Para agregar _Container Template Kaniko_

- En _Panel de Control_ -> _Administrar Jenkins_ -> _kubernetes_ -> _Pod Templates_, **pod-default**

  - Add Container
    - Name: kaniko
    - Docker image: gcr.io/kaniko-project/executor:debug
    - Working directory: /home/jenkins/agent
    - Command to run: cat
    - Arguments to pass to the command: _En blanco_
    - Allocate pseudo-TTY: true

Y añadimos la _stage_ al `Jenkinsfile`

```Groovy
stage('Build & Publish Container Image') {
    when {
        anyOf {
            branch 'main'
            branch 'develop'
        }
    }
    steps {
        container('kaniko') {
            println '05# Stage - Build & Publish Container Image'
            println '(develop y main): Build container image with Kaniko & Publish to container registry.'
            sh '''
                /kaniko/executor \
                --context `pwd` \
                --insecure \
                --dockerfile Dockerfile \
                --destination=nexus-service:8082/repository/docker/spring-petclinic:3.3.0-SNAPSHOT \
                --destination=nexus-service:8082/repository/docker/spring-petclinic:latest \
                --build-arg VERSION=3.3.0-SNAPSHOT.jar
            '''
        }
    }
}
```

Una vez subidos los cambios al repositorio en **GitHub** lanza una nueva construcción en **Jenkins**

Si todo va como debe y accedes a los repositorios de **Nexus** observaras que los artefactos se encuentran ahí

Hasta aquí el CI

#### Stage de despliegue

Continuamos con el CD. En esta _stage_ desplegaremos un contenedor en MicroK8s de la imagen de contenedor la aplicación `spring-petclinic` generada en el punto anterior. Por fin veremos la aplicación en funcionamiento

Para lleva a cabo esta etapa necesitaremos tener instalada la utilidad de gestión kubectl en un contenedor.

A continuación se describe el proceso de instalación de kubectl extraído de [https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/]

> ¡Atención! NO REALIZAR ESTA INSTALACIÓN. Se realiza dentro de la _stage_ de despliegue en el contenedor por defecto `jnlp`

##### Configuración para ejecutar kubectl en contenedor - Install kubectl binary with curl on Linux

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

---

Con la instalación de kubectl nuestra stage queda del siguiente modo.

```Groovy
stage('Deploy petclinic') {
    when {
        anyOf {
            branch 'main'
            branch 'develop'
        }
    }
    steps {
        println '06# Stage - Deploy petclinic'
        println '(develop y main): Deploy petclinic app to MicroK8s.'
        sh '''
            curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
            chmod +x kubectl
            mkdir -p ~/.local/bin
            #mv ./kubectl ~/.local/bin/kubectl
            
            ./kubectl version --client
            ./kubectl get all

            ./kubectl create deployment petclinic --image <IP_SERVICIO_NEXUS>:8082/repository/docker/spring-petclinic:latest || \
              echo 'Deployment petclinic already exists, creating service...'
            ./kubectl expose deployment petclinic --port 8080 --target-port 8080 --selector app=petclinic --type ClusterIP --name petclinic

            ./kubectl get all
        '''
    }
}
```

Añade la _stage_ cambiando `<IP_SERVICIO_NEXUS>` por la IP del servicio **Nexus**, al `Jenkinsfile` y sube al repositorio los cambios.

> ¡Atención! En este punto no bastara con copiar `Jenkinsfile.publish` y sustituir el archivo `Jenkinsfile` del repositorio del _tema_ al repositorio de la aplicación `spring-petclinic` deberás sustituir `<IP_SERVICIO_NEXUS>` por la IP del servicio **Nexus**. Más adelante ya realizaremos un automatismo para no tener que hacer esta sustitución a mano.

En este punto es necesario resaltar que se debe usar le IP y no el nombre de servicio ya que la acción _pull_ de la imagen del contenedor se delega directamente en el **MicroK8s** y en el host que lo alberga y este no accede al servicio de resolución de nombres internos del nodo al que si acceden los PODs desplegados en el

Realiza Nueva construcción en **Jenkins**, esperamos a que finalice y examinamos el registro, por el final veremos la IP de acceso al servicio **_petclinic_**

---

A continuación deberíamos realizar test de usabilidad, de rendimiento, de carga, de interfaz de usuario...

Nos conformaremos con comprobar que accedemos mediante navegador a la aplicación. Y pasaremos a promocionar el código a la rama de producción, a la rama `main`

### Construcción de la Jenkins Pipeline - flujo CI/CD - Rama Main

Aprovechando que vamos a incluir una nueva _stage_ de promoción de código, realizaremos una serie de cambios en la configuración del **Jenkins** y en nuestra **_Pipeline_**

- _Token_ de acceso de **GitHub** para **Jenkins**

  Como necesitaremos actualizar el repositorio desde **Jenkins** será necesario obtener un _token_ de acceso al repositorio en **GitHub**

- Añadir credenciales a la tarea _Spring Petclinic_

- Configurar _Azure Plugin Key Vault_
  Para usar el _token_ de **GitHub** en nuestra _Pipeline_

- Añadir Stages de promoción de código

  - Uso de variables de entorno  
    Se parametrizara mediante variables de entorno la _versión de software_
  
  - Uso de métodos
    Se añade un método para obtener la versión del archivo pom.xml

#### Generar un Token Personal de Acceso (GitHub Token v2)

- Ve a **GitHub**, pulsa en la esquina superior derecha sobre  tu _Avatar_ -> _Settings_

  En el menú de la izquierda al final _Developer settings_ -> _Personal access tokens_ -> _Fine-grained tokens (Beta)_

- Haz clic en _Generate new token_

- _Repository access_ - _Only select repositories_ - Selecciona el repositorio `spring-petclinic`

- En _Permissions_ - _Repository permissions_ - A todos los premiso(27) conceder Access: _Read and write_
  _Administration_, _Codespaces metadata_ y _Metadata_ serán la excepción conceder _Access:Read-only_

- Una vez creado, **copia el token**. No podrás volver obtener el token, en caso de perderlo necesitaras crear otro

#### Añadir credenciales a la tarea Spring Petclinic

Procedemos a añadir credenciales a la tarea _Spring Petclinic_ esto nos permitirá poder realizar cambios en el repositorio GitHub desde nuestra Pipeline

 _Panel de Control_ -> _Spring Petclinic_ -> _Configure_

En _Branch Sources_, _GitHub_, _Credentials_, Botón _+Add_ _Jenkins_

- Domain: Global credentials (unrestricted)
- Kind: Username with password
- Scope: Global(Jenkins, nodes, items, all child items, etc)
- Username: nuestro usuario de GitGub
- Password: El token de GitHub
- ID: githubcredential
- Description: GitHub Credential
- Botón _Validate_
- Botón _Add_

En _Credentials_ seleccionamos la credencial recién creada, Botón _Save_

### Configuración del Azure Plugin Key Vault

Para configurar el acceso a un _Key Vault_ en **Azure**, será necesario disponer de un _Service Principal_, con permiso para dicho acceso. Con el fin de acelerar, el proceso y no requerir una cuenta de **Azure**, se facilitará uno ya previamente creado

Pasos seguidos en **Azure** (omitir durante el seguimiento del _tema_, ya realizados)

- Creación del _Service principal_ mediante la _CLI de Azure_ con asignación de rol

- Creación del _Key Vault_ y asignación de permisos de lectura al _Service Principal_
  
  ```Bash
  az ad sp create-for-rbac --name "azure-sp" \
  --role "Key Vault Secrets User" \
  --scopes "/subscriptions/<AQUI EL Subscription ID>/resourceGroups/<AQUí el nombre del resourceGroups>/providers/Microsoft.KeyVault/vaults/<AQUÍ el nombre del Key Vault>"
  ```

- Adición de el/los _token_ de **GitHub** como _secretos_ al _Key Vault_
  Se solicitarán los tokens de Github para ser incluidos en el _Key Vault_

En **Jenkins**  realizar las siguientes pasos

- _Panel de Control_ -> _Administrar Jenkins_ -> _System_, Sección _Azure Key Vault Plugin_

  - Key Vault URL: Se facilitará
  - Credential ID: Pulsar sobre _+ Add_ -> _Jenkins_
    - Domain: Global credentials (unrestricted)
    - Kind: Azure Service Principal
    - Scope: Global(Jenkins, nodes, items, all child items, etc)
    - Subscription ID: Se facilitará
    - Client ID: Se facilitará
    - Client Secret: Se facilitará
    - Tenant ID: Se facilitará
    - ID: azuresp
    - Description: Azure Service Principal for Key Vault access
    - Botón _Verify Service Principal_
    Si todo está correcto
    - Botón _Add_
  - Credential ID: Pulsar sobre _none_ y seleccionar _azuresp (Azure Service Principal for Key Vault access)_
  - Botón _Test Connection_
  - Botón _Save_

Si vamos a  _Panel de Control_ -> _Administrar Jenkins_ -> _Credentials_ Comprobaremos que se listan los identificadores de los secretos del _Key Vault_ en **Azure**

#### Stages de promoción de código

Nuestra promoción consistirá en quitar el sufijo `-SNAPSHOT` y promocionar a rama `main` en caso de encontrarnos en rama `develop`
Si estamos en rama `main` subimos en uno la versión añadimos el sufijo `-SNAPSHOT` y promocionamos a rama `develop`

Añadiremos una variable global al inicio de la _Pipeline_ y un método al final, para obtener la versión del archivo `pom.xml`. Invocaremos el método desde nuestra _stage_ inicial `Check Environment`

Variable global

```Groovy
CURRENT_VERSION = ""
```

Definir envar con el usuario de GitHub

```Groovy
environment {
  GIT_USERNAME="<AQUÍ tu usuario de GitHub>"
}
```

Método

```Groovy
def currentVersion() {
    def pomVersion = sh(script: "mvn help:evaluate -Dexpression=project.version -q -DforceStdout", returnStdout: true).trim()
    return pomVersion
}
```

Línea que se añade a la _stag_ `Check Environment`, ¡OJO! dentro de clausula _script_ dentro del contenedor `maven`. Ya que estamos, actualizamos la _stage_ añadiendo configuración para **GIT**

```Groovy
stage('Check Environment') {
    steps {
        container('maven') {
            sh '''
                java -version
                mvn -version
                pwd
                env
                git config --global --add safe.directory $PWD
                git config --global --add user.email "jenkins@domain.local"
                git config --global --add user.name "Jenkins Server"
            '''

            script {
                CURRENT_VERSION = currentVersion()
            }
        }
        println '01# Stage - Check Environment'
        println '(develop y main):  Checking environment Java & Maven versions.'
        sh 'java -version'
        echo CURRENT_VERSION
    }
}
```

Y agregamos las dos stages de promoción

En caso de encontrarnos en rama `develop` promocionamos a `main`

```Groovy
stage('Release Promotion Branch main') {
    when {
        branch 'develop'
    }
    steps {
        container('maven') {
            println '07# Stage - Release Promotion Branch main'
            println '(develop): Release Promotion Branch main update pom version'
            withCredentials([string(credentialsId: 'github-token', variable: 'GIT_PASSWORD')]) {
                script {
                    def releaseVersion = CURRENT_VERSION.replace('-SNAPSHOT', '')
                    def repoUrl = GIT_URL.replace('https://', "https://${GIT_USERNAME}:${GIT_PASSWORD}@")
                    sh "mvn versions:set -DnewVersion=${releaseVersion}"
                    sh 'git add pom.xml'
                    sh "git commit -m 'Jenkins promotion ${releaseVersion}'"
                    sh 'git checkout -b main || git checkout main'
                    sh "git remote set-url origin ${repoUrl}"
                    sh 'git push origin main'
                }
            }
        }
    }
}
```

En caso de encontrarnos en rama `main` promocionamos a `develop`

```Groovy
stage('Release Promotion Branch develop') {
    when {
        branch 'main'
    }
    steps {
        container('maven') {
            println '07# Stage - Release Promotion Branch develop'
            println '(main): Release Promotion Branch develop update pom version'
            withCredentials([string(credentialsId: 'github-token', variable: 'GIT_PASSWORD')]) {
                script {
                    def (major, minor, patch) = CURRENT_VERSION.split('\\.')
                    def newSnapshotVersion = "${major}.${minor}.${patch.toInteger() + 1}-SNAPSHOT"
                    def repoUrl = GIT_URL.replace('https://', "https://${GIT_USERNAME}:${GIT_PASSWORD}@")
                    sh "mvn versions:set -DnewVersion=${newSnapshotVersion}"
                    sh 'git add pom.xml'
                    sh "git commit -m 'Jenkins promotion ${newSnapshotVersion}'"
                    sh 'git checkout -b develop || git checkout develop'
                    sh "git remote set-url origin ${repoUrl}"
                    sh 'git push origin develop'
                }
            }
        }
    }
}
```

También actualizaremos el resto de la _Pipeline_ para independizar la versión del código

Otra mejora consiste obtener de forma dinámica la IP del servicio **Nexus** en la _stage_ `Deploy petclinic`

Todos estos cambios los tienes en el archivo `Jenkisfile.promotion`

A estas alturas ya deberías saber que hacer para realizar una nueva construcción en **Jenkins** que refleje estos cambios

Si todo va bien deberías poder descubrir la rama main en **Jenkins** y lanzar una construcción

Al final podrá acceder a dos versiones de la aplicación una en el entorno de desarrollo y otra en el entorno de producción

Examina los _services_ en **MicroK8s**

---

## TIPs

### Resolviendo problemas de resolución de DNS en MicroK8s

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

### Ruta almacenamiento, a los PVCs en MicroK8s

`/var/snap/microk8s/common/default-storage`

### Clausula post de un Jenkinsfile

```Groovy
post {
        always {
            archiveArtifacts artifacts: 'build/libs/**/*.jar', fingerprint: true
            junit 'build/reports/**/*.xml'
        }
    }
```
user is not authorized to perform: iam:PassRole on resourcd: arn:aws:iam::***:role/service-role/my-test-lambda-role-xxxxxxxx with a explici deny in an identity-based policy

---




Secreto para docker registry

kubectl create secret docker-registry ecr-secret \
  --docker-server=006921246751.dkr.ecr.eu-north-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password)" \
  --docker-email=antonio.lledo@convotis.com


port-forward

kubectl port-forward service/jenkins 8080:8080

Log

kubectl get events -n namespace



microk8s config > ~/.kube/config


apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: deployment-ingress
  namespace: default # Namespace del deployment
spec:
  rules:
  - host: "my-microk8s-srv"  # IP del nodo MicroK8s
    http:
      paths:
      - path: /jenkins
        pathType: Prefix
        backend:
          service:
            name: jenkins # Nombre del servicio asociado al deployment
            port:
              number: 8080  # Puerto en el que está expuesto el servicio
