job "outlook-service" {
  datacenters = ["dc1"]
  type = "service"
  
  update {
    max_parallel = 1
    min_healthy_time = "30s"
    healthy_deadline = "5m"
    auto_revert = true
  }

  group "outlook-group" {
    count = 1
    
    network {
      port "http" {
        static = 5004
        to = 5004
      }
    }
    
    service {
      name = "outlook-service"
      tags = ["api", "backend", "outlook", "v1"]
      port = "http"
      
      check {
        name = "health"
        type = "http"
        path = "/health"
        interval = "30s"
        timeout = "5s"
      }
    }

    task "outlook-api" {
      driver = "docker"
      
      config {
        image = "DOCKER_IMAGE_PLACEHOLDER:IMAGE_TAG_PLACEHOLDER"
        ports = ["http"]
      }
      
      env {
        SERVICE_NAME = "outlook-service"
        SERVICE_PORT = "5004"
        NODE_ENV = "production"
      }
      
      resources {
        cpu = 500
        memory = 512
      }
    }
  }
}
