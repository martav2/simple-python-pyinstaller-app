# Entregable Terraform + Jenkins + SCV

---

> Autor: Marta Villa López
> 

---

En este documento se explican los ficheros y comandos necesarios para realizar un despliegue de una aplicación Python mediante un pipeline de Jenkins. Utilizaremos Jenkins desplegado en un contenedor Docker y un agente Docker in Docker para ejecutar el pipeline.

El despliegue de los dos contenedores Docker necesarios, Docker in Docker y Jenkins, se realizará mediante Terraform, mientras que para la creación de la imagen personalizada de Jenkins se utilizará un Dockerfile, para el control de versiones se utilizará Git.

En primer lugar se realizará una explicación de los ficheros de configuración y sus comandos y a continuación se explicarán los pasos para llevar a cabo el despliegue.

# Ficheros de configuración

## Fichero `Dockerfile`

Para la creación de la imagen personalizada de Jenkins utilizaremos el siguiente fichero Dockerfile:

```docker
FROM jenkins/jenkins:2.479.2-jdk17
USER root
RUN apt-get update && apt-get install -y lsb-release
RUN curl -fsSLo /usr/share/keyrings/docker-archive-keyring.asc \
    https://download.docker.com/linux/debian/gpg
RUN echo "deb [arch=$(dpkg --print-architecture) \
    signed-by=/usr/share/keyrings/docker-archive-keyring.asc] \
    https://download.docker.com/linux/debian \
    $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
RUN apt-get update && apt-get install -y docker-ce-cli
USER jenkins
RUN jenkins-plugin-cli --plugins "blueocean docker-workflow token-macro json-path-api"
```

### **1. Definición de la imagen base:**

```docker
FROM jenkins/jenkins:2.479.2-jdk17
```

- Este comando indica que la imagen base será `jenkins/jenkins` versión `2.479.2-jdk17`.

---

### **2. Cambiar al usuario root:**

```docker
USER root
```

- Cambia el usuario actual dentro del contenedor a **root**. Esto es necesario porque se requieren privilegios de superusuario, para instalar paquetes o modificar configuraciones del sistema.

---

### **3. Actualizar y instalar `lsb-release`:**

```docker
RUN apt-get update && apt-get install -y lsb-release
```

- Actualiza los índices de los paquetes (`apt-get update`) e instala el paquete `lsb-release`, que proporciona información sobre la distribución de Linux instalada (en este caso, Debian).

---

### **4. Descargar e instalar la clave GPG de Docker:**

```docker
RUN curl -fsSLo /usr/share/keyrings/docker-archive-keyring.asc \
    https://download.docker.com/linux/debian/gpg
```

- Este comando descarga la clave GPG pública de Docker desde su repositorio oficial y la guarda en `/usr/share/keyrings/docker-archive-keyring.asc`.
    - Esta clave es necesaria para verificar la autenticidad de los paquetes de Docker que se instalarán más adelante.

---

### **5. Agregar el repositorio de Docker a la lista de fuentes de APT:**

```docker
RUN echo "deb [arch=$(dpkg --print-architecture) \
    signed-by=/usr/share/keyrings/docker-archive-keyring.asc] \
    https://download.docker.com/linux/debian \
    $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
```

- Este comando agrega el repositorio oficial de Docker para Debian a la lista de fuentes de APT en el contenedor.

---

### **6. Actualizar los índices de los paquetes e instalar Docker CLI:**

```docker
RUN apt-get update && apt-get install -y docker-ce-cli
```

- Este comando actualiza los índices de APT y luego instala `docker-ce-cli`**,** la herramienta de línea de comandos de Docker, necesaria para interactuar con Docker desde dentro del contenedor.

---

### **7. Volver al usuario `jenkins`:**

```docker
USER jenkins
```

- Después de realizar las configuraciones que requieren privilegios de root, por seguridad se vuelve a cambiar al usuario predeterminado, ‘jenkins’.

---

### **8. Instalar plugins de Jenkins:**

```docker
RUN jenkins-plugin-cli --plugins "blueocean docker-workflow token-macro json-path-api"
```

- Este comando instala varios plugins en Jenkins usando la herramienta `jenkins-plugin-cli`:
    - **`blueocean`**: Es un conjunto de plugins que proporciona una interfaz de usuario moderna y mejorada para Jenkins.
    - **`docker-workflow`**: Es un plugin para trabajar con Jenkins pipelines usando Docker, lo que facilita la integración de contenedores Docker en los pipelines de Jenkins.
    - **`token-macro`**: Este plugin permite usar macros y variables en Jenkins, lo que es útil para personalizar las configuraciones y parámetros.
    - **`json-path-api`**: Este plugin proporciona funciones de procesamiento de JSON, que es útil para manipular datos JSON dentro de los pipelines de Jenkins.

---

## Fichero `main.tf`

Este fichero Terraform `main.tf` contiene los comandos necesarios para crear un entorno de Jenkins utilizando Docker-in-Docker, configurando tanto la red, los volúmenes y los puertos necesarios para la comunicación entre contenedores y con el host.

```
terraform {
    required_providers {
        docker = {
            source = "kreuzwerker/docker"
            version = "~> 3.0.1"
        }
    }
}

provider "docker" {
    host = "npipe:////.//pipe//docker_engine"
}

# Volumenes
resource "docker_volume" "docker_certs_volume" {
  name = "docker_certs_volume"
}

resource "docker_volume" "jenkins_data_volume" {
  name = "jenkins_data_volume"
}

# Red jenkins_network
resource "docker_network" "jenkins_network" {
    name = "jenkins_network"
}

# Docker in Docker

resource "docker_image" "dind" {
    name = "docker:dind"
    keep_locally = false
}

resource "docker_container" "dind_container" {
    image = docker_image.dind.image_id
    name  = "dind_container"
    attach = false
    rm = true
    privileged = true
    env = [
        "DOCKER_TLS_CERTDIR=/certs",
    ]

    networks_advanced {
        name = docker_network.jenkins_network.name
        aliases = ["docker"]
    }

    volumes {
        volume_name    = docker_volume.docker_certs_volume.name
        container_path = "/certs/client"
    }

    volumes {
        volume_name    = docker_volume.jenkins_data_volume.name
        container_path = "/var/jenkins_home"
    }

    ports {
        internal = 2376
        external = 2376
    }

    ports {
        internal = 3000
        external = 3000
    }

    ports {
        internal = 5000
        external = 5000
    }
}

# Jenkins

resource "docker_image" "jenkins_image" {
  name         = "jenkins_image"
  keep_locally = false
}

resource "docker_container" "myjenkins" {
    image = docker_image.jenkins_image.image_id
    name  = "myjenkins"
    attach  = false
    restart = "on-failure"

  env = [
    "DOCKER_TLS_CERTDIR=/certs",
    "DOCKER_CERT_PATH=/certs/client",
    "DOCKER_HOST=tcp://docker:2376",
    "DOCKER_TLS_VERIFY=1",
    "JAVA_OPTS=-Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true",
  ]
  
  networks_advanced {
    name = docker_network.jenkins_network.name
  }

  volumes {
    volume_name    = docker_volume.docker_certs_volume.name
    container_path = "/certs/client"
  }

  volumes {
    volume_name    = docker_volume.jenkins_data_volume.name
    container_path = "/var/jenkins_home"
  }

  volumes {
    volume_name    = "jenkins_home_volume"
    container_path = "/home"
  }

  ports {
    internal = 8080
    external = 8080
  }

  ports {
    internal = 50000
    external = 50000
  }
}
```

### **1. Definición de la configuración de Terraform y el proveedor de Docker:**

```hcl
terraform {
    required_providers {
        docker = {
            source = "kreuzwerker/docker"
            version = "~> 3.0.1"
        }
    }
}
```

- Se define el **proveedor de Docker** en Terraform: Se especifica que se usará el proveedor `docker` de la fuente `kreuzwerker` en su versión `~> 3.0.1`.

---

### **2. Proveedor de Docker:**

```hcl
provider "docker" {
    host = "npipe:////.//pipe//docker_engine"
}
```

- Se configura el proveedor de Docker.
    - **`host`**: establece la conexión con el daemon de Docker, utilizando un "named pipe" en Windows.

---

### **3. Creación de volúmenes de Docker:**

```hcl
resource "docker_volume" "docker_certs_volume" {
  name = "docker_certs_volume"
}

resource "docker_volume" "jenkins_data_volume" {
  name = "jenkins_data_volume"
}
```

- Se crean dos volúmenes de Docker para persistir la información:
    - **`docker_certs_volume`**: Este volumen almacenará los certificados Docker necesarios para la comunicación segura entre contenedores.
    - **`jenkins_data_volume`**: Este volumen se usará para persistir los datos de Jenkins.

---

### **4. Creación de una red Docker:**

```hcl
resource "docker_network" "jenkins_network" {
    name = "jenkins_network"
}
```

- Se crea una red Docker llamada **`jenkins_network`** para permitir que los contenedores se comuniquen entre sí. La red es esencial para que Jenkins y Docker-in-Docker interactúen de manera efectiva dentro del mismo entorno.

---

### **5. Configuración Docker-in-Docker:**

### 5.1. Imagen de Docker-in-Docker:

```hcl
resource "docker_image" "dind" {
    name = "docker:dind"
    keep_locally = false
}
```

- Se define una imagen Docker para Docker-in-Docker (DinD).
    - **`docker:dind`**: Es una imagen oficial de Docker que permite ejecutar Docker dentro de un contenedor.
    - **`keep_locally = false`**: Esto asegura que la imagen no se mantendrá localmente después de la creación del contenedor.

### 5.2. Contenedor Docker-in-Docker:

```hcl
resource "docker_container" "dind_container" {
    image = docker_image.dind.image_id
    name  = "dind_container"
    attach = false
    rm = true
    privileged = true
    env = [
        "DOCKER_TLS_CERTDIR=/certs",
    ]
    
    networks_advanced {
        name = docker_network.jenkins_network.name
    }
    
    volumes {
        volume_name    = docker_volume.docker_certs_volume.name
        container_path = "/certs/client"
    }
    
    volumes {
        volume_name    = docker_volume.jenkins_data_volume.name
        container_path = "/var/jenkins_home"
    }
    
    ports {
        internal = 2376
        external = 2376
    }
    
    ports {
        internal = 3000
        external = 3000
    }
    
    ports {
        internal = 5000
        external = 5000
    }
}
```

- Crea el contenedor **`dind_container`** basado en la imagen DinD.
    - **`image = docker_image.dind.image_id`**: Especifica la imagen que se utilizará para crear el contenedor.Hace referencia al recurso `docker_image "dind"` definido previamente, que utiliza la imagen oficial de Docker para DinD (`docker:dind`).
    - **`name = "dind_container"`**: Define el nombre del contenedor como `dind_container`.
    - **`attach = false`**: Especifica que no se adjunta la salida estándar a la ejecución de Terraform.
    - **`rm = true`**: Especifica que el contenedor debe eliminarse automáticamente cuando se detenga.
    - **`privileged = true`**: Configura el contenedor en modo privilegiado, esto es necesario para el funcionamiento de Docker-in-Docker.
    - **`env`**: Se configura la variable de entorno `DOCKER_TLS_CERTDIR=/certs`, que indica dónde se encuentran los certificados TLS para asegurar la comunicación entre Docker y otros contenedores.
    - **`networks_advanced`**: El contenedor se conecta a la red `jenkins_network`, permitiendo que la comunicación con el contenedor de Jenkins.
    - **`volumes`**: Se montan dos volúmenes:
        - **`docker_certs_volume`** en `/certs/client` para los certificados de Docker.
        - **`jenkins_data_volume`** en `/var/jenkins_home` para persistir los datos de Jenkins.
    - **`ports`**: Se exponen los puertos `2376`, `3000` y `5000` para la comunicación segura con Docker.

---

### **6. Configuración de Jenkins:**

### 6.1. Imagen de Jenkins:

```hcl
resource "docker_image" "jenkins_image" {
  name         = "jenkins_image"
  keep_locally = false
}
```

- Define una imagen Docker para Jenkins llamada **`jenkins_image`**. Esta imagen se usará para crear un contenedor de Jenkins dentro del entorno Docker-in-Docker.
    - **`keep_locally = false`**: Indica que la imagen de Jenkins no se mantendrá localmente después de la creación del contenedor.

### 6.2. Contenedor Jenkins:

```hcl
resource "docker_container" "myjenkins" {
    image = docker_image.jenkins_image.image_id
    name  = "myjenkins"
    attach  = false
    restart = "on-failure"
    env = [
        "DOCKER_TLS_CERTDIR=/certs",
        "DOCKER_CERT_PATH=/certs/client",
        "DOCKER_HOST=tcp://docker:2376",
        "DOCKER_TLS_VERIFY=1",
        "JAVA_OPTS=-Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true",
    ]
    
    networks_advanced {
        name = docker_network.jenkins_network.name
    }
    
    volumes {
        volume_name    = docker_volume.jenkins_data_volume.name
        container_path = "/var/jenkins_home"
    }
    
    volumes {
        volume_name    = docker_volume.docker_certs_volume.name
        container_path = "/certs/client"
    }
    
    volumes {
        volume_name    = "jenkins_home_volume"
        container_path = "/home"
    }
    
    ports {
        internal = 8080
        external = 8080
    }
    
    ports {
        internal = 50000
        external = 50000
    }
}
```

- Crea un contenedor **`myjenkins`** que ejecuta Jenkins dentro del entorno Docker-in-Docker.
    - **`image = docker_image.jenkins_image.image_id`** : Usa la imagen definida previamente en `docker_image` , `jenkins_image` .
    - **`name = "myjenkins"`**: Define el nombre del contenedor como `myjenkins`.
    - **`attach = false`**: Especifica que no se adjunta la salida estándar a la ejecución de Terraform.
    - **`restart = "on-failure"`**: Configura una política de reinicio automática en caso de errores.
    - **`env`**: Se configuran varias variables de entorno:
        - **`DOCKER_TLS_CERTDIR`** y **`DOCKER_CERT_PATH`**: Indicando los certificados para la comunicación segura con Docker.
        - **`DOCKER_HOST`**: Define la dirección del host de Docker, que en este caso es el contenedor de Docker-in-Docker.
        - **`JAVA_OPTS`**: Se configura una opción de Java para permitir ciertos tipos de checkout en Jenkins.
    - **`networks_advanced`**: El contenedor se conecta a la red `jenkins_network` para la comunicación entre contenedores.
    - **`volumes`**: Se montan tres volúmenes:
        - **`docker_certs_volume`** en `/certs/client` para los certificados Docker.
        - **`jenkins_data_volume`** en `/var/jenkins_home` para los datos de Jenkins.
        - **`jenkins_home_volume`** en `/home` para almacenar otros datos de Jenkins.
    - **`ports`**: Se exponen los puertos `8080` y `50000`
        - **`8080`**: Expuesto para acceder a la interfaz web de Jenkins.
        - **`50000`**: Expuesto para la comunicación con agentes remotos de Jenkins.

---

## Fichero `Jenkinsfile`

```
pipeline {
    agent none
    options {
        skipStagesAfterUnstable()
    }
    stages {
        stage('Build') {
            agent {
                docker {
                    image 'python:3.12.0-alpine3.18'
                }
            }
            steps {
                sh 'python -m py_compile sources/add2vals.py sources/calc.py'
                stash(name: 'compiled-results', includes: 'sources/*.py*')
            }
        }
        stage('Test') {
            agent {
                docker {
                    image 'qnib/pytest'
                }
            }
            steps {
                sh 'py.test --junit-xml test-reports/results.xml sources/test_calc.py'
            }
            post {
                always {
                    junit 'test-reports/results.xml'
                }
            }
        }
        stage('Deliver') {
            agent any
            environment {
                VOLUME = '$(pwd)/sources:/src'
                IMAGE = 'cdrx/pyinstaller-linux:python2'
            }
            steps {
                dir(path: env.BUILD_ID) {
                    unstash(name: 'compiled-results')
                    sh "docker run --rm -v ${VOLUME} ${IMAGE} 'pyinstaller -F add2vals.py'"
                }
            }
            post {
                success {
                    archiveArtifacts "${env.BUILD_ID}/sources/dist/add2vals"
                    sh "docker run --rm -v ${VOLUME} ${IMAGE} 'rm -rf build dist'"
                }
            }
        }
    }
}
```

### **Pipeline**

```groovy
pipeline {
    agent none
    options {
        skipStagesAfterUnstable()
    }
```

- **`pipeline`**: Define el bloque principal que encapsula toda la definición del pipeline en Jenkins.
- **`agent none`**: Especifica que no se asignará un agente de forma global. Cada etapa gestionará su propio agente.
- **`options`**: **`skipStagesAfterUnstable()`** : Indica que si alguna etapa resulta en un estado "Unstable", las siguientes etapas del pipeline no se ejecutarán.

---

### **Etapas (`stages`)**

1. **Build**: Compila el código Python y guarda los resultados compilados.
2. **Test**: Ejecuta pruebas unitarias con `pytest` y publica los resultados.
3. **Deliver**: Usa PyInstaller para empaquetar el script como un ejecutable autónomo y archiva el artefacto resultante.

### **Etapa `Build`**

```groovy
stage('Build') {
    agent {
        docker {
            image 'python:3.12.0-alpine3.18'
        }
    }
    steps {
        sh 'python -m py_compile sources/add2vals.py sources/calc.py'
        stash(name: 'compiled-results', includes: 'sources/*.py*')
    }
}
```

- **`stage('Build')`**: Define la etapa "Build", que se encargará de compilar el código Python.
- **`agent { docker { image 'python:3.12.0-alpine3.18' } }`**: La etapa se ejecuta dentro de un contenedor Docker basado en la imagen oficial **Python 3.12** sobre **Alpine Linux 3.18**.
- **`steps`**:
    - **`sh 'python -m py_compile sources/add2vals.py sources/calc.py'`**: Ejecuta el comando para compilar los scripts Python (`add2vals.py` y `calc.py`) en el directorio `sources`.
    - **`stash(name: 'compiled-results', includes: 'sources/*.py*')`**: Almacena los archivos compilados en `compiled-results` para que puedan ser reutilizados en etapas posteriores.

---

### **Etapa `Test`**

```groovy
stage('Test') {
    agent {
        docker {
            image 'qnib/pytest'
        }
    }
    steps {
        sh 'py.test --junit-xml test-reports/results.xml sources/test_calc.py'
    }
    post {
        always {
            junit 'test-reports/results.xml'
        }
    }
}
```

- **`stage('Test')`**: Define la etapa "Test", encargada de ejecutar pruebas unitarias.
- **`agent { docker { image 'qnib/pytest' } }`**: Usa un contenedor Docker basado en la imagen `qnib/pytest`, optimizada para ejecutar pruebas con `pytest`.
- **`steps`**: **`sh 'py.test --junit-xml test-reports/results.xml sources/test_calc.py'`**: Ejecuta los tests definidos en el archivo `sources/test_calc.py` usando `pytest` y guarda los resultados en el archivo `test-reports/results.xml`.
- **`post`**: **`always { junit 'test-reports/results.xml' }`**: Publica los resultados de las pruebas en Jenkins, usando el archivo generado previamente.

---

### **Etapa `Deliver`**

```groovy
stage('Deliver') {
    agent any
    environment {
        VOLUME = '$(pwd)/sources:/src'
        IMAGE = 'cdrx/pyinstaller-linux:python2'
    }
    steps {
        dir(path: env.BUILD_ID) {
            unstash(name: 'compiled-results')
            sh "docker run --rm -v ${VOLUME} ${IMAGE} 'pyinstaller -F add2vals.py'"
        }
    }
    post {
        success {
            archiveArtifacts "${env.BUILD_ID}/sources/dist/add2vals"
            sh "docker run --rm -v ${VOLUME} ${IMAGE} 'rm -rf build dist'"
        }
    }
}
```

- **`stage('Deliver')`**: Define la etapa de entrega, donde el script compilado se empaqueta como un ejecutable.
- **`agent any`**: Esta etapa se puede ejecutar en cualquier agente disponible de Jenkins.
- **`environment`**:
    - **`VOLUME = '$(pwd)/sources:/src'`**: Define un volumen que mapea el directorio local `sources` al directorio `/src` en el contenedor Docker.
    - **`IMAGE = 'cdrx/pyinstaller-linux:python2'`**: Especifica la imagen Docker que se usará en esta etapa, basada en PyInstaller con soporte para Python 2.
- **`steps`**:
    - **`dir(path: env.BUILD_ID)`**: Cambia el directorio de trabajo al ID de construcción actual (`env.BUILD_ID`), asegurando que los artefactos se organizan por cada ejecución de pipeline.
    - **`unstash(name: 'compiled-results')`**: Recupera los archivos compilados del stash `compiled-results`.
    - **`sh "docker run --rm -v ${VOLUME} ${IMAGE} 'pyinstaller -F add2vals.py'"`**: Ejecuta un contenedor Docker con la imagen PyInstaller para crear un ejecutable autónomo a partir del script `add2vals.py`.
- **`post`**: **`success`**:
    - **`archiveArtifacts "${env.BUILD_ID}/sources/dist/add2vals"`**: Archiva el ejecutable generado (`add2vals`) en Jenkins como un artefacto de construcción.
    - **`sh "docker run --rm -v ${VOLUME} ${IMAGE} 'rm -rf build dist'"`**: Limpia los directorios temporales (`build` y `dist`) dentro del volumen.

---

# Despliegue

## Construcción de la imagen personalizada de Jenkins

Construye una nueva imagen de Docker a partir del fichero Dockerfile creado anteriormente y le asigna a la imagen un nombre significativo (`jenkins_image` ) :

```powershell
docker build -t jenkins_image .
```

---

## Despliegue de contenedores con Terraform

Inicializamos un proyecto Terraform con el comando: 

```powershell
terraform init
```

Con esto se realizan varias tareas, la descarga de proveedores, la inicialización del estado y la validación de la configuración.

A continuación ejecutamos:

```powershell
terraform plan
```

Terraform escaneará los archivos de configuración, evaluará la infraestructura actual y generará un plan detallado de los cambios propuestos.

Aplicamos los archivos de configuración del directorio actual con:

```powershell
terraform apply
```

Comprobamos el estado actual de la infraestructura con:

```powershell
terraform show
```

## Fork del repositorio

Hacemos fork del siguiente repositorio de la aplicación Python: [https://github.com/jenkins-docs/simple-python-pyinstaller-app](https://github.com/jenkins-docs/simple-python-pyinstaller-app)

Nuestro repositorio es: [https://github.com/martav2/simple-python-pyinstaller-app/tree/main](https://github.com/martav2/simple-python-pyinstaller-app/tree/main)

## Acceso y configuración de Jenkins

En primer lugar abriremos en el navegador [http://localhost:8080/](http://localhost:8080/) para acceder a un asistente de configuración que nos guiará para desbloquear Jenkins, instalar plugins y crear el primer usuario administrador.

Una vez aparezca la página de Jenkins se nos solicitará un usuario y contraseña, la contraseña la encontraremos utilizando el comando:

```powershell
docker logs myjenkins
```

A continuación instalaremos los plugins sugeridos y crearemos el usuario administrador.

## Creación y ejecución del pipeline

Una vez finalizada la configuración inicial procederemos a la creación del pipeline:

1. Seleccionamos **Nuevo elemento** en el panel de control.
2. En **Ingresar un nombre de elemento** ponemos `simple-python-pyinstaller-app`
3. Seleccionamos **Pipeline**.
4. Añadimos una **descripción**.
5. En **Pipeline** > **Definición** seleccionamos **Pipeline script from SMC**.
    1. En **SMC** seleccionamos **Git**, introducimos la url a nuestro repositorio y especificamos la rama **main**.
6. Pulsamos **Guardar**.
7. Por último, seleccionamos **Construir ahora** en el panel izquierdo
