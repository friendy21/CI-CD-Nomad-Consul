#!/bin/bash

# Standardized Nomad Deployment Script
# Usage: ./deploy-service.sh <service-name> <docker-image> <image-tag> <service-port>

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to validate required parameters
validate_parameters() {
    if [ $# -ne 4 ]; then
        print_message $RED "❌ Usage: $0 <service-name> <docker-image> <image-tag> <service-port>"
        print_message $YELLOW "Example: $0 calendar-service friendy21/calendar-service main-abc123 5002"
        exit 1
    fi
}

# Function to validate environment
validate_environment() {
    local service_name=$1
    
    print_message $BLUE "🔍 Validating environment for $service_name..."
    
    # Check required environment variables
    if [ -z "$NOMAD_ADDR" ]; then
        print_message $RED "❌ NOMAD_ADDR environment variable is not set"
        exit 1
    fi
    
    if [ -z "$NOMAD_TOKEN" ]; then
        print_message $RED "❌ NOMAD_TOKEN environment variable is not set"
        exit 1
    fi
    
    # Test Nomad connectivity
    print_message $BLUE "🔗 Testing Nomad connectivity..."
    if ! nomad node status >/dev/null 2>&1; then
        print_message $RED "❌ Cannot connect to Nomad at $NOMAD_ADDR"
        print_message $YELLOW "🔍 Attempting to get Nomad status..."
        curl -s "$NOMAD_ADDR/v1/status/leader" || print_message $RED "Failed to get Nomad leader info"
        exit 1
    fi
    
    print_message $GREEN "✅ Environment validation passed"
}

# Function to find and validate HCL file
find_hcl_file() {
    local service_name=$1
    local hcl_filename="${service_name}.hcl"
    local expected_path="nomad/$hcl_filename"
    
    print_message $BLUE "🔍 Looking for HCL file: $hcl_filename"
    
    # Check expected location first
    if [ -f "$expected_path" ]; then
        print_message $GREEN "✅ Found HCL file at expected location: $expected_path"
        echo "$expected_path"
        return 0
    fi
    
    # Search entire repository
    print_message $YELLOW "⚠️ HCL file not found at expected location, searching repository..."
    local found_file=$(find . -name "$hcl_filename" -type f | head -1)
    
    if [ -n "$found_file" ]; then
        print_message $GREEN "✅ Found HCL file at: $found_file"
        echo "$found_file"
        return 0
    fi
    
    # Final fallback - list available HCL files
    print_message $RED "❌ $hcl_filename not found anywhere in repository"
    print_message $YELLOW "📁 Available HCL files:"
    find . -name "*.hcl" -type f || print_message $YELLOW "No .hcl files found"
    
    return 1
}

# Function to process HCL file
process_hcl_file() {
    local hcl_file=$1
    local docker_image=$2
    local image_tag=$3
    
    print_message $BLUE "🔄 Processing HCL file: $hcl_file"
    
    # Create backup
    local backup_file="${hcl_file}.backup.$(date +%s)"
    cp "$hcl_file" "$backup_file"
    print_message $BLUE "💾 Created backup: $backup_file"
    
    # Show original content (first 20 lines for brevity)
    print_message $BLUE "📄 Original HCL file preview:"
    echo "----------------------------------------"
    head -20 "$hcl_file"
    echo "----------------------------------------"
    
    # Replace placeholders
    print_message $BLUE "🔄 Replacing placeholders..."
    sed -i "s|IMAGE_TAG_PLACEHOLDER|$image_tag|g" "$hcl_file"
    sed -i "s|DOCKER_IMAGE_PLACEHOLDER|$docker_image|g" "$hcl_file"
    
    # Verify replacements
    print_message $BLUE "🔍 Verifying placeholder replacement..."
    if grep -q "PLACEHOLDER" "$hcl_file"; then
        print_message $RED "❌ Placeholder replacement failed. Remaining placeholders:"
        grep "PLACEHOLDER" "$hcl_file" | head -5
        print_message $YELLOW "📄 Restoring from backup..."
        cp "$backup_file" "$hcl_file"
        return 1
    fi
    
    print_message $GREEN "✅ Placeholders replaced successfully"
    
    # Show key sections of processed file
    print_message $BLUE "📄 Processed HCL file preview:"
    echo "----------------------------------------"
    grep -E "(job |image =|SERVICE_)" "$hcl_file" | head -10
    echo "----------------------------------------"
    
    return 0
}

# Function to validate and deploy job
validate_and_deploy() {
    local hcl_file=$1
    local service_name=$2
    local service_port=$3
    
    print_message $BLUE "🔍 Validating Nomad job..."
    if ! nomad job validate "$hcl_file"; then
        print_message $RED "❌ Job validation failed"
        print_message $YELLOW "📄 HCL file content:"
        echo "----------------------------------------"
        cat "$hcl_file"
        echo "----------------------------------------"
        return 1
    fi
    print_message $GREEN "✅ Job validation passed"
    
    # Submit job
    print_message $BLUE "🚀 Deploying $service_name..."
    if ! nomad job run "$hcl_file"; then
        print_message $RED "❌ Job submission failed"
        nomad job status "$service_name" 2>/dev/null || print_message $YELLOW "No previous job status available"
        return 1
    fi
    
    print_message $GREEN "✅ Job submitted successfully"
    return 0
}

# Function to monitor deployment
monitor_deployment() {
    local service_name=$1
    local service_port=$2
    local max_attempts=${3:-60}
    
    print_message $BLUE "⏳ Monitoring deployment of $service_name..."
    print_message $YELLOW "📊 Maximum wait time: $((max_attempts * 10)) seconds"
    
    local attempt=0
    local last_status=""
    local consecutive_running=0
    
    while [ $attempt -lt $max_attempts ]; do
        # Get job status with comprehensive error handling
        local status
        status=$(nomad job status "$service_name" 2>/dev/null | grep "^Status" | awk '{print $3}' 2>/dev/null || echo "unknown")
        
        # Only log status changes to reduce noise
        if [ "$status" != "$last_status" ]; then
            print_message $YELLOW "📊 Status update ($((attempt + 1))/$max_attempts): $status"
            last_status="$status"
            consecutive_running=0
        fi
        
        case "$status" in
            "running")
                consecutive_running=$((consecutive_running + 1))
                
                # Wait for stable running state
                if [ $consecutive_running -ge 3 ]; then
                    print_message $GREEN "✅ $service_name is running stably!"
                    
                    # Show deployment summary
                    print_message $BLUE "📊 Deployment summary:"
                    nomad job status "$service_name" | head -15
                    
                    # Optional health check
                    if [ -n "$service_port" ] && [ "$service_port" != "0" ]; then
                        check_service_health "$service_name" "$service_port"
                    fi
                    
                    return 0
                fi
                ;;
            "dead"|"failed")
                print_message $RED "❌ Deployment failed with status: $status"
                show_failure_details "$service_name"
                return 1
                ;;
            "pending")
                # Show detailed info periodically
                if [ $((attempt % 10)) -eq 0 ] && [ $attempt -gt 0 ]; then
                    print_message $YELLOW "📊 Still pending after $((attempt * 10)) seconds..."
                    nomad job status "$service_name" 2>/dev/null | head -8 || true
                fi
                ;;
            "unknown")
                if [ $attempt -eq 0 ]; then
                    print_message $YELLOW "⚠️ Cannot determine job status, service might not exist yet"
                fi
                ;;
        esac
        
        sleep 10
        attempt=$((attempt + 1))
    done
    
    # Timeout reached
    print_message $RED "❌ Deployment timed out after $((max_attempts * 10)) seconds"
    show_failure_details "$service_name"
    return 1
}

# Function to check service health
check_service_health() {
    local service_name=$1
    local service_port=$2
    
    print_message $BLUE "🏥 Performing health check for $service_name..."
    
    local health_url="http://localhost:$service_port/health"
    local max_health_attempts=5
    
    for health_attempt in $(seq 1 $max_health_attempts); do
        print_message $YELLOW "🔄 Health check attempt $health_attempt/$max_health_attempts..."
        
        if curl -f -s --max-time 10 "$health_url" >/dev/null 2>&1; then
            print_message $GREEN "✅ Health check passed for $service_name"
            
            # Get health info if possible
            local health_info
            health_info=$(curl -s --max-time 5 "$health_url" 2>/dev/null || echo "{}")
            if echo "$health_info" | jq . >/dev/null 2>&1; then
                print_message $BLUE "📊 Service health info:"
                echo "$health_info" | jq .
            fi
            return 0
        fi
        
        if [ $health_attempt -lt $max_health_attempts ]; then
            sleep 15
        fi
    done
    
    print_message $YELLOW "⚠️ Health check failed, but service appears to be running"
    print_message $YELLOW "🔍 This might be normal if the service is still initializing"
    return 0
}

# Function to show failure details
show_failure_details() {
    local service_name=$1
    
    print_message $YELLOW "📋 Gathering failure details for $service_name..."
    
    # Job status
    print_message $BLUE "📊 Job Status:"
    nomad job status "$service_name" 2>/dev/null || print_message $YELLOW "No job status available"
    
    echo ""
    
    # Recent allocations
    print_message $BLUE "📋 Recent Allocations:"
    nomad job allocs "$service_name" 2>/dev/null | head -10 || print_message $YELLOW "No allocations available"
    
    echo ""
    
    # Get the most recent allocation ID and show logs
    local alloc_id
    alloc_id=$(nomad job allocs "$service_name" -json 2>/dev/null | jq -r '.[0].ID' 2>/dev/null || echo "")
    
    if [ -n "$alloc_id" ] && [ "$alloc_id" != "null" ]; then
        print_message $BLUE "📝 Recent Allocation Logs (last 50 lines):"
        nomad alloc logs -n 50 "$alloc_id" 2>/dev/null || print_message $YELLOW "No logs available"
    fi
}

# Function to cleanup
cleanup() {
    print_message $BLUE "🧹 Performing cleanup..."
    
    # Remove backup files older than 1 hour
    find . -name "*.hcl.backup.*" -type f -mmin +60 -delete 2>/dev/null || true
    
    print_message $GREEN "✅ Cleanup completed"
}

# Main execution function
main() {
    local service_name=$1
    local docker_image=$2
    local image_tag=$3
    local service_port=$4
    
    print_message $GREEN "🚀 Starting deployment of $service_name"
    print_message $BLUE "📦 Image: $docker_image:$image_tag"
    print_message $BLUE "🔌 Port: $service_port"
    print_message $BLUE "🎯 Nomad: $NOMAD_ADDR"
    echo ""
    
    # Validate environment
    validate_environment "$service_name"
    
    # Find HCL file
    local hcl_file
    hcl_file=$(find_hcl_file "$service_name") || {
        print_message $RED "❌ Cannot find HCL file for $service_name"
        exit 1
    }
    
    # Process HCL file
    if ! process_hcl_file "$hcl_file" "$docker_image" "$image_tag"; then
        print_message $RED "❌ Failed to process HCL file"
        exit 1
    fi
    
    # Validate and deploy
    if ! validate_and_deploy "$hcl_file" "$service_name" "$service_port"; then
        print_message $RED "❌ Failed to deploy $service_name"
        exit 1
    fi
    
    # Monitor deployment
    if ! monitor_deployment "$service_name" "$service_port" 60; then
        print_message $RED "❌ Deployment monitoring failed"
        exit 1
    fi
    
    # Cleanup
    cleanup
    
    print_message $GREEN "🎉 Successfully deployed $service_name!"
    print_message $BLUE "🌐 Service should be available at: http://localhost:$service_port"
    
    return 0
}

# Script entry point
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    validate_parameters "$@"
    main "$@"
fi
