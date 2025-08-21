job "teams-service" {
  datacenters = ["dc1"]
  type = "service"
  
  update {
    max_parallel = 1
    min_healthy_time = "30s"
    healthy_deadline = "5m"
    auto_revert = true
  }

  group "teams-group" {
    count = 1
    
    network {
      port "http" {
        static = 5005
        to = 5005
      }
    }
    
    service {
      name = "teams-service"
      tags = ["api", "backend", "teams", "v1"]
      port = "http"
      
      check {
        name = "health"
        type = "http"
        path = "/health"
        interval = "30s"
        timeout = "5s"
      }
    }

    task "teams-api" {
      driver = "docker"
      
      config {
        image = "DOCKER_IMAGE_PLACEHOLDER:IMAGE_TAG_PLACEHOLDER"
        ports = ["http"]
      }
      
      env {
        SERVICE_NAME = "teams-service"
        SERVICE_PORT = "5005"
        NODE_ENV = "production"
      }
      
      resources {
        cpu = 500
        memory = 512
      }
    }
  }
}
