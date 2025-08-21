job "outlook-service" {
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

  group "outlook-group" {
    count = 1
    
    # Enhanced restart policy
    restart {
      attempts = 5
      interval = "10m"
      delay    = "45s"
      mode     = "fail"
    }
    
    # Reschedule policy for failed allocations
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
        static = 5004
        to     = 5004
      }
    }
    
    service {
      name = "outlook-service"
      tags = ["api", "backend", "outlook", "email", "v1", "http"]
      port = "http"
      
      # Primary HTTP health check
      check {
        name     = "outlook-health-http"
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
      
      # Secondary TCP health check
      check {
        name     = "outlook-health-tcp"
        type     = "tcp"
        interval = "15s"
        timeout  = "5s"
      }
      
      # Service metadata for discovery
      meta {
        version      = "1.0.0"
        environment  = "production"
        protocol     = "http"
        capabilities = "email,calendar-integration"
      }
    }

    task "outlook-api" {
      driver = "docker"
      
      # Graceful shutdown settings
      kill_timeout = "45s"
      kill_signal  = "SIGTERM"
      
      config {
        image        = "DOCKER_IMAGE_PLACEHOLDER:IMAGE_TAG_PLACEHOLDER"
        ports        = ["http"]
        force_pull   = false
        
        # Enhanced logging configuration
        logging {
          type = "json-file"
          config {
            max-size = "15m"
            max-file = "5"
            labels   = "service,version,environment"
          }
        }
        
        # Container health check
        healthcheck {
          test         = ["CMD", "curl", "-f", "http://localhost:5004/health"]
          interval     = "30s"
          timeout      = "10s"
          retries      = 3
          start_period = "60s"
        }
      }
      
      # Environment variables
      env {
        SERVICE_NAME = "outlook-service"
        SERVICE_PORT = "5004"
        LOG_LEVEL    = "INFO"
        NODE_ENV     = "production"
        VERSION      = "1.0.0"
        
        # Python optimization
        PYTHONUNBUFFERED = "1"
        PYTHONDONTWRITEBYTECODE = "1"
        
        # Flask production settings
        FLASK_ENV = "production"
        WORKERS   = "2"
        THREADS   = "4"
        
        # Email service specific
        EMAIL_BATCH_SIZE = "50"
        MAX_EMAIL_SIZE   = "25MB"
      }
      
      # Resource allocation
      resources {
        cpu        = 600
        memory     = 768
        memory_max = 1024
      }
      
      # Lifecycle management
      lifecycle {
        hook    = "prestart"
        sidecar = false
      }
    }
  }
}
