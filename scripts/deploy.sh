#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SERVICES=("user" "calendar" "onedrive" "outlook" "teams")
NOMAD_ADDR=${NOMAD_ADDR:-"http://localhost:4646"}
CONSUL_ADDR=${CONSUL_ADDR:-"http://localhost:8500"}

print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

check_prerequisites() {
    print_message $BLUE "🔍 Checking prerequisites..."
    
    # Check if Nomad is accessible
    if ! curl -f -s $NOMAD_ADDR/v1/status/leader > /dev/null; then
        print_message $RED "❌ Nomad is not accessible at $NOMAD_ADDR"
        exit 1
    fi
    
    # Check if Consul is accessible
    if ! curl -f -s $CONSUL_ADDR/v1/status/leader > /dev/null; then
        print_message $RED "❌ Consul is not accessible at $CONSUL_ADDR"
        exit 1
    fi
    
    print_message $GREEN "✅ Prerequisites check passed"
}

deploy_service() {
    local service=$1
    local port=$((5001 + $(printf '%s\n' "${SERVICES[@]}" | grep -n "^$service$" | cut -d: -f1) - 1))
    
    print_message $BLUE "🚀 Deploying $service-service..."
    
    # Run Nomad job
    if nomad job run nomad/${service}.hcl; then
        print_message $GREEN "✅ $service-service job submitted successfully"
        
        # Wait for deployment
        local timeout=300
        local elapsed=0
        while [ $elapsed -lt $timeout ]; do
            if nomad job status ${service}-service | grep -q "Status.*running"; then
                print_message $GREEN "🎉 $service-service is running!"
                
                # Health check
                if ./scripts/health-check.sh ${service}-service $port 10; then
                    print_message $GREEN "✅ $service-service passed health check"
                    return 0
                else
                    print_message $YELLOW "⚠️ $service-service failed health check but is running"
                    return 0
                fi
            fi
            
            sleep 10
            elapsed=$((elapsed + 10))
            print_message $YELLOW "⏳ Waiting for $service-service to be ready... (${elapsed}s/${timeout}s)"
        done
        
        print_message $RED "❌ $service-service deployment timed out"
        return 1
    else
        print_message $RED "❌ Failed to deploy $service-service"
        return 1
    fi
}

deploy_all_services() {
    print_message $BLUE "🚀 Starting deployment of all services..."
    
    local failed_services=()
    
    for service in "${SERVICES[@]}"; do
        if deploy_service $service; then
            print_message $GREEN "✅ $service-service deployed successfully"
        else
            print_message $RED "❌ $service-service deployment failed"
            failed_services+=($service)
        fi
        echo ""
    done
    
    # Summary
    if [ ${#failed_services[@]} -eq 0 ]; then
        print_message $GREEN "🎉 All services deployed successfully!"
        
        print_message $BLUE "📊 Service Status Summary:"
        for service in "${SERVICES[@]}"; do
            local port=$((5001 + $(printf '%s\n' "${SERVICES[@]}" | grep -n "^$service$" | cut -d: -f1) - 1))
            echo "   • $service-service: http://localhost:$port"
        done
        
        echo ""
        print_message $BLUE "🎛️ Management UIs:"
        echo "   • Nomad UI: $NOMAD_ADDR"
        echo "   • Consul UI: $CONSUL_ADDR"
        
    else
        print_message $RED "❌ Some services failed to deploy: ${failed_services[*]}"
        exit 1
    fi
}

show_status() {
    print_message $BLUE "📊 Current Service Status:"
    echo ""
    
    for service in "${SERVICES[@]}"; do
        local port=$((5001 + $(printf '%s\n' "${SERVICES[@]}" | grep -n "^$service$" | cut -d: -f1) - 1))
        
        if nomad job status ${service}-service &>/dev/null; then
            local status=$(nomad job status ${service}-service | grep "Status" | awk '{print $3}')
            if [ "$status" = "running" ]; then
                print_message $GREEN "✅ $service-service: $status (port $port)"
            else
                print_message $YELLOW "⚠️ $service-service: $status (port $port)"
            fi
        else
            print_message $RED "❌ $service-service: not deployed"
        fi
    done
}

# Main execution
case "${1:-deploy}" in
    "deploy")
        check_prerequisites
        deploy_all_services
        ;;
    "status")
        show_status
        ;;
    "service")
        if [ -z "$2" ]; then
            echo "Usage: $0 service <service-name>"
            echo "Available services: ${SERVICES[*]}"
            exit 1
        fi
        check_prerequisites
        deploy_service "$2"
        ;;
    "help")
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  deploy     - Deploy all services (default)"
        echo "  status     - Show status of all services"
        echo "  service    - Deploy a specific service"
        echo "  help       - Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0                    # Deploy all services"
        echo "  $0 status            # Show service status"
        echo "  $0 service user      # Deploy only user service"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
