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