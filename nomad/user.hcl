job "user-service" {
  datacenters = ["dc1"]
  type = "service"
  
  update {
    max_parallel = 1
    min_healthy_time = "30s"
    healthy_deadline = "5m"
    progress_deadline = "10m"
    auto_revert = true
  }

  group "user-group" {
    count = 1
    
    restart {
      attempts = 3
      interval = "5m"
      delay = "30s"
      mode = "fail"
    }
    
    network {
      port "http" {
        static = 5001
        to = 5001
      }
    }
    
    service {
      name = "user-service"
      tags = ["api", "backend", "user", "v1"]
      port = "http"
      
      check {
        name = "health"
        type = "http"
        path = "/health"
        interval = "30s"
        timeout = "5s"
        
        check_restart {
          limit = 3
          grace = "90s"
          ignore_warnings = false
        }
      }
      
      check {
        name = "tcp-check"
        type = "tcp"
        interval = "15s"
        timeout = "3s"
      }
    }

    task "user-api" {
      driver = "docker"
      
      config {
        image = "DOCKER_IMAGE_PLACEHOLDER:IMAGE_TAG_PLACEHOLDER"
        ports = ["http"]
        
        logging {
          type = "json-file"
          config {
            max-size = "10m"
            max-file = "3"
          }
        }
      }
      
      env {
        SERVICE_NAME = "user-service"
        SERVICE_PORT = "5001"
        LOG_LEVEL = "INFO"
        NODE_ENV = "production"
        VERSION = "1.0.0"
      }
      
      resources {
        cpu = 500
        memory = 512
      }
      
      kill_timeout = "30s"
    }
  }
}
