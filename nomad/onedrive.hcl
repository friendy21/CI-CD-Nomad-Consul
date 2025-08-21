job "onedrive-service" {
  datacenters = ["dc1"]
  type = "service"
  
  update {
    max_parallel = 1
    min_healthy_time = "30s"
    healthy_deadline = "5m"
    auto_revert = true
  }

  group "onedrive-group" {
    count = 1
    
    network {
      port "http" {
        static = 5003
        to = 5003
      }
    }
    
    service {
      name = "onedrive-service"
      tags = ["api", "backend", "onedrive", "v1"]
      port = "http"
      
      check {
        name = "health"
        type = "http"
        path = "/health"
        interval = "30s"
        timeout = "5s"
      }
    }

    task "onedrive-api" {
      driver = "docker"
      
      config {
        image = "DOCKER_IMAGE_PLACEHOLDER:IMAGE_TAG_PLACEHOLDER"
        ports = ["http"]
      }
      
      env {
        SERVICE_NAME = "onedrive-service"
        SERVICE_PORT = "5003"
        NODE_ENV = "production"
      }
      
      resources {
        cpu = 500
        memory = 512
      }
    }
  }
}
