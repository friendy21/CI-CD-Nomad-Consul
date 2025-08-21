job "user-service" {
  datacenters = ["dc1"]
  type = "service"
  
  # Comprehensive update strategy
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

  group "user-group" {
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
        static = 5001
        to     = 5001
      }
    }
    
    service {
      name = "user-service"
      tags = ["api", "backend", "user", "authentication", "v1", "http"]
      port = "http"
      
      # Primary HTTP health check
      check {
        name     = "user-health-http"
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
        name     = "user-health-tcp"
        type     = "tcp"
        interval = "15s"
        timeout  = "5s"
      }
      
      # Additional readiness check
      check {
        name     = "user-readiness"
        type     = "http"
        path     = "/users"
        method   = "GET"
        interval = "60s"
        timeout  = "15s"
      }
      
      # Service metadata for discovery
      meta {
        version      = "1.0.0"
        environment  = "production"
        protocol     = "http"
        capabilities = "user-management,authentication"
        priority     = "high"
      }
      
      # Service weights for load balancing
      weights {
        passing = 10
        warning = 1
      }
    }

    task "user-api" {
      driver = "docker"
      
      # Enhanced shutdown configuration
      kill_timeout = "60s"
      kill_signal  = "SIGTERM"
      
      config {
        image        = "DOCKER_IMAGE_PLACEHOLDER:IMAGE_TAG_PLACEHOLDER"
        ports        = ["http"]
        force_pull   = false
        
        # Comprehensive logging setup
        logging {
          type = "json-file"
          config {
            max-size = "20m"
            max-file = "7"
            labels   = "service,version,environment,instance"
          }
        }
        
        # Container health check
        healthcheck {
          test         = ["CMD", "curl", "-f", "http://localhost:5001/health"]
          interval     = "30s"
          timeout      = "10s"
          retries      = 3
          start_period = "90s"
        }
        
        # Security configuration
        cap_drop = ["ALL"]
        cap_add  = ["NET_BIND_SERVICE"]
      }
      
      # Comprehensive environment configuration
      env {
        SERVICE_NAME = "user-service"
        SERVICE_PORT = "5001"
        LOG_LEVEL    = "INFO"
        NODE_ENV     = "production"
        VERSION      = "1.0.0"
        
        # Python optimization
        PYTHONUNBUFFERED = "1"
        PYTHONDONTWRITEBYTECODE = "1"
        PYTHONPATH = "/app"
        
        # Flask production settings
        FLASK_ENV     = "production"
        FLASK_DEBUG   = "false"
        WORKERS       = "3"
        THREADS       = "4"
        WORKER_CLASS  = "sync"
        
        # User service specific
        PASSWORD_MIN_LENGTH = "8"
        SESSION_TIMEOUT     = "3600"
        MAX_LOGIN_ATTEMPTS  = "5"
        TOKEN_EXPIRY        = "24h"
        
        # Performance tuning
        GUNICORN_WORKERS        = "3"
        GUNICORN_WORKER_CONNECTIONS = "100"
        GUNICORN_MAX_REQUESTS   = "1000"
        GUNICORN_TIMEOUT        = "30"
        
        # Security settings
        SECURE_HEADERS = "true"
        CORS_ENABLED   = "true"
        RATE_LIMITING  = "true"
      }
      
      # Enhanced resource allocation
      resources {
        cpu        = 800
        memory     = 1024
        memory_max = 1536
      }
      
      # Lifecycle management
      lifecycle {
        hook    = "prestart"
        sidecar = false
      }
      
      # Template for dynamic configuration (optional)
      template {
        data = <<EOF
{{- range service "database" }}
DATABASE_URL=postgresql://user:pass@{{ .Address }}:{{ .Port }}/userdb
{{- end }}
EOF
        destination = "local/app.env"
        env         = true
        change_mode = "restart"
      }
      
      # Artifact for additional configuration files (optional)
      artifact {
        source      = "https://raw.githubusercontent.com/your-org/configs/main/user-service.conf"
        destination = "local/config/"
        mode        = "file"
        options {
          checksum = "sha256:abc123..."
        }
      }
    }
  }
}
