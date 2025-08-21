job "onedrive-service" {
  datacenters = ["dc1"]
  type = "service"
  
  # Enhanced update strategy
  update {
    max_parallel      = 1
    min_healthy_time  = "45s"
    healthy_deadline  = "8m"
    progress_deadline = "15m"
    auto_revert       = true
    auto_promote      = false
    canary            = 0
    stagger           = "30s"
  }

  group "onedrive-group" {
    count = 1
    
    # Enhanced restart policy
    restart {
      attempts = 5
      interval = "10m"
      delay    = "45s"
      mode     = "fail"
    }
    
    # Reschedule failed allocations
    reschedule {
      attempts       = 3
      interval       = "24h"
      delay          = "30s"
      delay_function = "exponential"
      max_delay      = "10m"
      unlimited      = false
    }
    
    network {
      port "http" {
        static = 5003
        to     = 5003
      }
    }
    
    service {
      name = "onedrive-service"
      tags = ["api", "backend", "onedrive", "storage", "v1", "http"]
      port = "http"
      
      # Primary health check
      check {
        name     = "onedrive-health-http"
        type     = "http"
        path     = "/health"
        interval = "30s"
        timeout  = "10s"
        
        check_restart {
          limit           = 4
          grace           = "90s"
          ignore_warnings = false
        }
      }
      
      # Secondary TCP check
      check {
        name     = "onedrive-health-tcp"
        type     = "tcp"
        interval = "15s"
        timeout  = "5s"
      }
      
      # Service metadata
      meta {
        version     = "1.0.0"
        environment = "production"
        protocol    = "http"
        capabilities = "file-storage,sharing"
      }
    }

    task "onedrive-api" {
      driver = "docker"
      
      # Graceful shutdown configuration
      kill_timeout = "45s"
      kill_signal  = "SIGTERM"
      
      config {
        image        = "DOCKER_IMAGE_PLACEHOLDER:IMAGE_TAG_PLACEHOLDER"
        ports        = ["http"]
        force_pull   = false
        
        # Enhanced logging
        logging {
          type = "json-file"
          config {
            max-size = "15m"
            max-file = "5"
            labels   = "service,version,environment"
          }
        }
        
        # Health check at container level
        healthcheck {
          test         = ["CMD", "curl", "-f", "http://localhost:5003/health"]
          interval     = "30s"
          timeout      = "10s"
          retries      = 3
          start_period = "60s"
        }
      }
      
      # Environment configuration
      env {
        SERVICE_NAME = "onedrive-service"
        SERVICE_PORT = "5003"
        LOG_LEVEL    = "INFO"
        NODE_ENV     = "production"
        VERSION      = "1.0.0"
        
        # Python optimization
        PYTHONUNBUFFERED = "1"
        PYTHONDONTWRITEBYTECODE = "1"
        
        # Flask configuration
        FLASK_ENV = "production"
        WORKERS   = "2"
        THREADS   = "4"
        
        # Storage configuration
        MAX_FILE_SIZE = "100MB"
        STORAGE_BACKEND = "local"
      }
      
      # Resource allocation
      resources {
        cpu        = 600
        memory     = 768
        memory_max = 1024
      }
      
      # Lifecycle hooks
      lifecycle {
        hook    = "prestart"
        sidecar = false
      }
    }
  }
}
