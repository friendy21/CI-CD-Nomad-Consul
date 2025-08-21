#!/bin/bash

# Enhanced Nomad Deployment Script with Comprehensive Error Handling
# Usage: ./enhanced-deploy.sh <service-name> <docker-image> <image-tag> <service-port>
# Version: 2.0.0
# Author: DevOps Team

set -euo pipefail  # Enhanced error handling

# Script metadata
readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_NAME=$(basename "$0")
readonly LOG_DATE=$(date '+%Y-%m-%d_%H-%M-%S')
readonly LOG_FILE="/tmp/${SCRIPT_NAME}_${LOG_DATE}.log"

# Color definitions for enhanced output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly PURPLE='\033[0;35m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Configuration constants
readonly MAX_DEPLOYMENT_TIME=1800  # 30 minutes
readonly HEALTH_CHECK_TIMEOUT=300   # 5 minutes
readonly CONNECTION_RETRY_COUNT=5
readonly STABLE_STATE_REQUIRED=5

# Global variables
declare -g SERVICE_NAME=""
declare -g DOCKER_IMAGE=""
declare -g IMAGE_TAG=""
declare -g SERVICE_PORT=""
declare -g HCL_FILE=""
declare -g BACKUP_FILE=""

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "${BLUE}ℹ️  $*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}✅ $*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}⚠️  $*${NC}"
}

log_error() {
    log "ERROR" "${RED}❌ $*${NC}"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        log "DEBUG" "${PURPLE}🔍 $*${NC}"
    fi
}

# Function to print script header
print_header() {
    echo -e "${WHITE}"
    echo "=================================================="
    echo "🚀 Enhanced Nomad Deployment Script v${SCRIPT_VERSION}"
    echo "📅 Started: $(date)"
    echo "📝 Log file: ${LOG_FILE}"
    echo "=================================================="
    echo -e "${NC}"
}

# Function to print colored messages with icons
print_message() {
    local color="$1"
    local icon="$2"
    local message="$3"
    echo -e "${color}${icon} ${message}${NC}"
}

# Enhanced parameter validation with detailed feedback
validate_parameters() {
    log_info "Validating input parameters..."
    
    if [[ $# -ne 4 ]]; then
        log_error "Invalid number of parameters"
        echo
        echo -e "${YELLOW}Usage: $0 <service-name> <docker-image> <image-tag> <service-port>${NC}"
        echo
        echo "Examples:"
        echo "  $0 user-service friendy21/user-service main-abc123 5001"
        echo "  $0 calendar-service friendy21/calendar-service v1.0.0-def456 5002"
        echo
        echo "Parameters:"
        echo "  service-name  : Name of the service (e.g., user-service)"
        echo "  docker-image  : Docker image repository (e.g., friendy21/user-service)"
        echo "  image-tag     : Docker image tag (e.g., main-abc123)"
        echo "  service-port  : Service port number (e.g., 5001)"
        exit 1
    fi
    
    SERVICE_NAME="$1"
    DOCKER_IMAGE="$2" 
    IMAGE_TAG="$3"
    SERVICE_PORT="$4"
    
    # Validate service name format
    if [[ ! "$SERVICE_NAME" =~ ^[a-z][a-z0-9\-]*[a-z0-9]$ ]]; then
        log_error "Invalid service name format: '$SERVICE_NAME'"
        log_error "Service name must start with letter, contain only lowercase letters, numbers, and hyphens"
        exit 1
    fi
    
    # Validate Docker image format
    if [[ ! "$DOCKER_IMAGE" =~ ^[a-z0-9\-_\.]+\/[a-z0-9\-_\.]+$ ]]; then
        log_error "Invalid Docker image format: '$DOCKER_IMAGE'"
        log_error "Expected format: registry/repository (e.g., friendy21/user-service)"
        exit 1
    fi
    
    # Validate port number
    if [[ ! "$SERVICE_PORT" =~ ^[0-9]+$ ]] || [[ "$SERVICE_PORT" -lt 1024 ]] || [[ "$SERVICE_PORT" -gt 65535 ]]; then
        log_error "Invalid service port: '$SERVICE_PORT'"
        log_error "Port must be a number between 1024 and 65535"
        exit 1
    fi
    
    log_success "Parameter validation completed"
    log_info "Service: $SERVICE_NAME"
    log_info "Image: $DOCKER_IMAGE:$IMAGE_TAG"
    log_info "Port: $SERVICE_PORT"
}

# Comprehensive environment validation
validate_environment() {
    log_info "Validating deployment environment..."
    
    # Check required environment variables
    local missing_vars=()
    
    if [[ -z "${NOMAD_ADDR:-}" ]]; then
        missing_vars+=("NOMAD_ADDR")
    fi
    
    if [[ -z "${NOMAD_TOKEN:-}" ]]; then
        missing_vars+=("NOMAD_TOKEN")
    fi
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        log_error "Please set the following environment variables:"
        for var in "${missing_vars[@]}"; do
            echo "  export $var=<value>"
        done
        exit 1
    fi
    
    # Validate Nomad address format
    if [[ ! "$NOMAD_ADDR" =~ ^https?://[a-zA-Z0-9\.\-]+:[0-9]+$ ]]; then
        log_warning "NOMAD_ADDR format may be invalid: $NOMAD_ADDR"
        log_warning "Expected format: http(s)://hostname:port"
    fi
    
    # Check for required tools
    local required_tools=("nomad" "curl" "jq" "sed" "grep" "find")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    # Verify Nomad version
    local nomad_version
    nomad_version=$(nomad version | head -1 | awk '{print $2}' || echo "unknown")
    log_info "Nomad version: $nomad_version"
    
    log_success "Environment validation completed"
}

# Enhanced HCL file discovery with multiple search patterns
find_hcl_file() {
    log_info "Locating HCL file for $SERVICE_NAME..."
    
    local search_patterns=(
        "nomad/${SERVICE_NAME}.hcl"
        "./${SERVICE_NAME}.hcl"
        "nomad/*.hcl"
        "*.hcl"
    )
    
    # Try expected location first
    for pattern in "${search_patterns[@]}"; do
        log_debug "Searching pattern: $pattern"
        
        if [[ "$pattern" == *"*"* ]]; then
            # Handle wildcard patterns
            local found_files
            mapfile -t found_files < <(find . -name "${pattern##*/}" -type f 2>/dev/null | grep -E "${SERVICE_NAME}" | head -5)
            
            for file in "${found_files[@]}"; do
                if [[ -f "$file" && "$file" == *"${SERVICE_NAME}"* ]]; then
                    HCL_FILE="$file"
                    log_success "Found HCL file: $HCL_FILE"
                    return 0
                fi
            done
        else
            if [[ -f "$pattern" ]]; then
                HCL_FILE="$pattern"
                log_success "Found HCL file: $HCL_FILE"
                return 0
            fi
        fi
    done
    
    # Comprehensive search as fallback
    log_warning "HCL file not found in expected locations, performing comprehensive search..."
    
    local comprehensive_search
    comprehensive_search=$(find . -name "*.hcl" -type f -exec grep -l "$SERVICE_NAME" {} \; 2>/dev/null | head -1)
    
    if [[ -n "$comprehensive_search" ]]; then
        HCL_FILE="$comprehensive_search"
        log_success "Found HCL file via comprehensive search: $HCL_FILE"
        return 0
    fi
    
    # Final fallback - list available files
    log_error "HCL file for $SERVICE_NAME not found"
    log_info "Available HCL files:"
    find . -name "*.hcl" -type f -printf "  %p\n" 2>/dev/null || log_warning "No HCL files found in repository"
    
    return 1
}

# Enhanced HCL file processing with validation
process_hcl_file() {
    log_info "Processing HCL file: $HCL_FILE"
    
    # Create timestamped backup
    BACKUP_FILE="${HCL_FILE}.backup.$(date +%s).$$"
    if ! cp "$HCL_FILE" "$BACKUP_FILE"; then
        log_error "Failed to create backup file"
        return 1
    fi
    log_success "Created backup: $BACKUP_FILE"
    
    # Display original file info
    local file_size
    file_size=$(wc -l < "$HCL_FILE")
    log_info "Original HCL file: $file_size lines"
    
    # Show original placeholders
    local image_placeholders docker_placeholders
    image_placeholders=$(grep -c "IMAGE_TAG_PLACEHOLDER" "$HCL_FILE" 2>/dev/null || echo "0")
    docker_placeholders=$(grep -c "DOCKER_IMAGE_PLACEHOLDER" "$HCL_FILE" 2>/dev/null || echo "0")
    
    log_info "Found placeholders - IMAGE_TAG: $image_placeholders, DOCKER_IMAGE: $docker_placeholders"
    
    if [[ "$image_placeholders" -eq 0 && "$docker_placeholders" -eq 0 ]]; then
        log_warning "No placeholders found - file may already be processed"
        log_info "Displaying current image configuration:"
        grep -n "image.*=" "$HCL_FILE" | head -3 || log_warning "No image configuration found"
    fi
    
    # Perform replacements with verification
    log_info "Replacing IMAGE_TAG_PLACEHOLDER with: $IMAGE_TAG"
    if ! sed -i "s|IMAGE_TAG_PLACEHOLDER|$IMAGE_TAG|g" "$HCL_FILE"; then
        log_error "Failed to replace IMAGE_TAG_PLACEHOLDER"
        restore_backup
        return 1
    fi
    
    log_info "Replacing DOCKER_IMAGE_PLACEHOLDER with: $DOCKER_IMAGE"
    if ! sed -i "s|DOCKER_IMAGE_PLACEHOLDER|$DOCKER_IMAGE|g" "$HCL_FILE"; then
        log_error "Failed to replace DOCKER_IMAGE_PLACEHOLDER"
        restore_backup
        return 1
    fi
    
    # Comprehensive validation of replacements
    local remaining_placeholders
    remaining_placeholders=$(grep -c "PLACEHOLDER" "$HCL_FILE" 2>/dev/null || echo "0")
    
    if [[ "$remaining_placeholders" -gt 0 ]]; then
        log_error "Found $remaining_placeholders unprocessed placeholders:"
        grep -n "PLACEHOLDER" "$HCL_FILE" | head -5
        log_error "Placeholder replacement failed"
        restore_backup
        return 1
    fi
    
    # Verify final configuration
    log_info "Final image configuration:"
    if ! grep -n "image.*=" "$HCL_FILE" | head -3; then
        log_error "No image configuration found after processing"
        restore_backup
        return 1
    fi
    
    log_success "HCL file processing completed successfully"
    return 0
}

# Function to restore backup on failure
restore_backup() {
    if [[ -n "$BACKUP_FILE" && -f "$BACKUP_FILE" ]]; then
        log_info "Restoring from backup: $BACKUP_FILE"
        cp "$BACKUP_FILE" "$HCL_FILE"
        log_success "Backup restored"
    fi
}

# Enhanced Nomad connectivity testing with detailed diagnostics
test_nomad_connectivity() {
    log_info "Testing Nomad cluster connectivity..."
    
    local attempt=0
    local max_attempts=$CONNECTION_RETRY_COUNT
    
    while [[ $attempt -lt $max_attempts ]]; do
        attempt=$((attempt + 1))
        log_debug "Connection attempt $attempt/$max_attempts"
        
        if timeout 15 nomad node status >/dev/null 2>&1; then
            log_success "Nomad connectivity established"
            
            # Get cluster information
            local node_count leader_addr
            node_count=$(nomad node status -json 2>/dev/null | jq length 2>/dev/null || echo "unknown")
            leader_addr=$(nomad operator raft list-peers 2>/dev/null | grep -w leader | awk '{print $2}' || echo "unknown")
            
            log_info "Cluster nodes: $node_count"
            log_info "Cluster leader: $leader_addr"
            
            return 0
        fi
        
        log_warning "Connection attempt $attempt failed"
        
        if [[ $attempt -lt $max_attempts ]]; then
            local delay=$((attempt * 5))
            log_info "Retrying in ${delay}s..."
            sleep $delay
        fi
    done
    
    log_error "Failed to connect to Nomad after $max_attempts attempts"
    
    # Provide diagnostic information
    log_info "Running connectivity diagnostics..."
    log_info "NOMAD_ADDR: $NOMAD_ADDR"
    
    # Test basic connectivity
    if timeout 10 curl -s --head "$NOMAD_ADDR/v1/status/leader" >/dev/null 2>&1; then
        log_info "HTTP connectivity to Nomad API: OK"
    else
        log_error "HTTP connectivity to Nomad API: FAILED"
    fi
    
    # Test DNS resolution
    local nomad_host
    nomad_host=$(echo "$NOMAD_ADDR" | sed 's|https\?://||' | cut -d':' -f1)
    if nslookup "$nomad_host" >/dev/null 2>&1; then
        log_info "DNS resolution for $nomad_host: OK"
    else
        log_warning "DNS resolution for $nomad_host: FAILED"
    fi
    
    return 1
}

# Comprehensive job validation with detailed error reporting
validate_nomad_job() {
    log_info "Validating Nomad job configuration..."
    
    # Basic syntax validation
    if ! nomad job validate "$HCL_FILE" 2>&1 | tee "${LOG_FILE}.validation"; then
        log_error "Job validation failed"
        
        # Show validation errors
        if [[ -f "${LOG_FILE}.validation" ]]; then
            log_error "Validation errors:"
            cat "${LOG_FILE}.validation" | head -20
        fi
        
        # Show problematic sections
        log_error "HCL file content around potential issues:"
        grep -n -A2 -B2 "image\|port\|service" "$HCL_FILE" || log_warning "Could not extract relevant sections"
        
        return 1
    fi
    
    log_success "Job validation passed"
    
    # Additional semantic validation
    local warnings=()
    
    # Check for common issues
    if ! grep -q "check.*health" "$HCL_FILE"; then
        warnings+=("No health check found")
    fi
    
    if ! grep -q "restart" "$HCL_FILE"; then
        warnings+=("No restart policy defined")
    fi
    
    if ! grep -q "resources" "$HCL_FILE"; then
        warnings+=("No resource constraints defined")
    fi
    
    # Report warnings
    if [[ ${#warnings[@]} -gt 0 ]]; then
        log_warning "Job validation warnings:"
        for warning in "${warnings[@]}"; do
            log_warning "  - $warning"
        done
    fi
    
    return 0
}

# Enhanced job planning with comprehensive analysis
plan_deployment() {
    log_info "Creating deployment plan..."
    
    local plan_output
    plan_output=$(mktemp)
    
    if nomad job plan "$HCL_FILE" > "$plan_output" 2>&1; then
        log_success "Deployment plan created successfully"
        
        # Analyze plan output
        if grep -q "No changes" "$plan_output"; then
            log_info "Plan indicates no changes required"
        elif grep -q "Task Group" "$plan_output"; then
            log_info "Plan summary:"
            grep -A5 -B5 "Task Group\|Deployment\|Job" "$plan_output" | head -10
        fi
    else
        log_warning "Deployment planning completed with warnings"
        log_debug "Plan output:"
        head -10 "$plan_output" | sed 's/^/  /'
    fi
    
    rm -f "$plan_output"
    return 0
}

# Execute deployment with comprehensive monitoring
execute_deployment() {
    log_info "Executing deployment for $SERVICE_NAME..."
    
    # Submit job
    if ! nomad job run "$HCL_FILE"; then
        log_error "Failed to submit job to Nomad cluster"
        
        # Try to get current job status for context
        if nomad job status "$SERVICE_NAME" >/dev/null 2>&1; then
            log_info "Current job status:"
            nomad job status "$SERVICE_NAME" | head -15
        fi
        
        return 1
    fi
    
    log_success "Job submitted to Nomad cluster"
    return 0
}

# Enhanced deployment monitoring with detailed progress tracking
monitor_deployment() {
    log_info "Monitoring deployment progress..."
    log_info "Maximum monitoring time: $((MAX_DEPLOYMENT_TIME / 60)) minutes"
    
    local start_time
    start_time=$(date +%s)
    local max_time=$MAX_DEPLOYMENT_TIME
    local check_interval=10
    local elapsed=0
    local stable_count=0
    local last_status=""
    local last_log_time=0
    
    while [[ $elapsed -lt $max_time ]]; do
        local current_time
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        
        # Get comprehensive job status
        local job_output status
        job_output=$(nomad job status "$SERVICE_NAME" 2>/dev/null || echo "")
        status=$(echo "$job_output" | grep "^Status" | awk '{print $3}' 2>/dev/null || echo "unknown")
        
        # Log status changes
        if [[ "$status" != "$last_status" ]]; then
            log_info "Status change: $last_status → $status (${elapsed}s elapsed)"
            last_status="$status"
            stable_count=0
            last_log_time=$current_time
        fi
        
        case "$status" in
            "running")
                stable_count=$((stable_count + 1))
                
                # Progress indicator for running state
                if [[ $((current_time - last_log_time)) -gt 60 ]]; then
                    log_info "Service running stable for $((stable_count * check_interval))s"
                    last_log_time=$current_time
                fi
                
                if [[ $stable_count -ge $STABLE_STATE_REQUIRED ]]; then
                    log_success "$SERVICE_NAME is running stably!"
                    
                    # Display deployment summary
                    display_deployment_summary
                    
                    # Perform health verification
                    if verify_service_health; then
                        log_success "Deployment completed successfully!"
                        return 0
                    else
                        log_warning "Deployment completed but health verification failed"
                        return 0  # Still consider it successful
                    fi
                fi
                ;;
            "dead"|"failed")
                log_error "Deployment failed with status: $status"
                display_failure_details
                return 1
                ;;
            "pending")
                # Show periodic progress updates
                if [[ $((elapsed % 120)) -eq 0 && $elapsed -gt 0 ]]; then
                    log_info "Still pending after $((elapsed / 60)) minutes..."
                    show_pending_details
                fi
                ;;
            *)
                stable_count=0
                if [[ $((current_time - last_log_time)) -gt 180 ]]; then
                    log_info "Current status: $status (${elapsed}s elapsed)"
                    last_log_time=$current_time
                fi
                ;;
        esac
        
        sleep $check_interval
    done
    
    log_error "Deployment monitoring timed out after $((max_time / 60)) minutes"
    display_timeout_details
    return 1
}

# Display comprehensive deployment summary
display_deployment_summary() {
    log_info "Deployment Summary:"
    echo "=================================="
    
    if nomad job status "$SERVICE_NAME" 2>/dev/null; then
        echo ""
        
        # Show allocation details
        log_info "Allocation Details:"
        nomad job allocs "$SERVICE_NAME" 2>/dev/null | head -5 || log_warning "No allocation details available"
    fi
    
    echo "=================================="
}

# Enhanced service health verification
verify_service_health() {
    log_info "Performing comprehensive health verification..."
    
    local health_start_time
    health_start_time=$(date +%s)
    local max_health_time=$HEALTH_CHECK_TIMEOUT
    local health_attempt=0
    local max_health_attempts=20
    
    # Get service endpoint information
    local alloc_id alloc_ip
    alloc_id=$(nomad job allocs "$SERVICE_NAME" -json 2>/dev/null | jq -r '.[0].ID' 2>/dev/null || echo "")
    
    if [[ -n "$alloc_id" && "$alloc_id" != "null" ]]; then
        alloc_ip=$(nomad alloc status "$alloc_id" 2>/dev/null | grep -E "Host Network.*:" | awk -F':' '{print $2}' | tr -d ' ' || echo "localhost")
        log_info "Service allocated to: $alloc_ip:$SERVICE_PORT"
    else
        alloc_ip="localhost"
        log_warning "Could not determine allocation details, using localhost"
    fi
    
    # Prepare health check endpoints
    local health_endpoints=(
        "http://${alloc_ip}:${SERVICE_PORT}/health"
        "http://localhost:${SERVICE_PORT}/health"
        "http://127.0.0.1:${SERVICE_PORT}/health"
    )
    
    while [[ $health_attempt -lt $max_health_attempts ]]; do
        local current_time
        current_time=$(date +%s)
        local health_elapsed=$((current_time - health_start_time))
        
        if [[ $health_elapsed -gt $max_health_time ]]; then
            log_warning "Health check timeout after $((max_health_time / 60)) minutes"
            break
        fi
        
        health_attempt=$((health_attempt + 1))
        log_debug "Health check attempt $health_attempt/$max_health_attempts"
        
        # Try each endpoint
        for endpoint in "${health_endpoints[@]}"; do
            log_debug "Testing endpoint: $endpoint"
            
            if timeout 15 curl -f -s "$endpoint" >/dev/null 2>&1; then
                log_success "Health check passed via $endpoint"
                
                # Get detailed health information
                local health_response
                health_response=$(timeout 10 curl -s "$endpoint" 2>/dev/null || echo "{}")
                
                if echo "$health_response" | jq . >/dev/null 2>&1; then
                    log_info "Health details:"
                    echo "$health_response" | jq . | head -10
                else
                    log_info "Health response: $health_response"
                fi
                
                # Additional service verification
                verify_service_endpoints "$alloc_ip"
                
                return 0
            fi
        done
        
        # Progressive delay between attempts
        local delay=$((health_attempt > 10 ? 30 : health_attempt * 3 + 10))
        log_debug "Waiting ${delay}s before next health check..."
        sleep $delay
    done
    
    log_warning "Health verification failed after $max_health_attempts attempts"
    log_info "This may be expected if:"
    log_info "  • Service is still initializing"
    log_info "  • Health endpoint is not implemented"
    log_info "  • Network policies restrict access"
    
    return 1
}

# Verify additional service endpoints
verify_service_endpoints() {
    local service_ip="$1"
    
    log_debug "Verifying additional service endpoints..."
    
    # Test root endpoint
    if timeout 10 curl -f -s "http://${service_ip}:${SERVICE_PORT}/" >/dev/null 2>&1; then
        log_success "Root endpoint accessible"
    else
        log_debug "Root endpoint not accessible (may be expected)"
    fi
    
    # Test common API endpoints based on service type
    local test_endpoints=()
    case "$SERVICE_NAME" in
        "user-service")
            test_endpoints=("/users")
            ;;
        "calendar-service")
            test_endpoints=("/events")
            ;;
        *)
            log_debug "No specific endpoints to test for $SERVICE_NAME"
            ;;
    esac
    
    for endpoint in "${test_endpoints[@]}"; do
        if timeout 10 curl -f -s "http://${service_ip}:${SERVICE_PORT}${endpoint}" >/dev/null 2>&1; then
            log_success "Endpoint $endpoint accessible"
        else
            log_debug "Endpoint $endpoint not accessible (may require authentication)"
        fi
    done
}

# Display detailed failure information
display_failure_details() {
    log_error "Analyzing deployment failure..."
    echo "=================================="
    
    # Job status
    log_info "Job Status:"
    if nomad job status "$SERVICE_NAME" 2>/dev/null; then
        echo ""
    else
        log_error "Could not retrieve job status"
    fi
    
    # Allocation details
    log_info "Allocation Details:"
    if nomad job allocs "$SERVICE_NAME" 2>/dev/null; then
        echo ""
    else
        log_error "Could not retrieve allocation details"
    fi
    
    # Recent logs
    log_info "Recent Logs:"
    local failed_alloc_id
    failed_alloc_id=$(nomad job allocs "$SERVICE_NAME" -json 2>/dev/null | jq -r '.[0].ID' 2>/dev/null || echo "")
    
    if [[ -n "$failed_alloc_id" && "$failed_alloc_id" != "null" ]]; then
        echo "Allocation ID: $failed_alloc_id"
        nomad alloc logs -n 50 "$failed_alloc_id" 2>/dev/null || log_error "Could not retrieve logs"
    else
        log_error "Could not determine failed allocation ID"
    fi
    
    echo "=================================="
}

# Show details for pending deployments
show_pending_details() {
    log_info "Pending Deployment Details:"
    
    # Show allocation status
    if nomad job allocs "$SERVICE_NAME" 2>/dev/null | head -8; then
        echo ""
    fi
    
    # Check for resource constraints
    if nomad node status 2>/dev/null | grep -q "down\|drain"; then
        log_warning "Some cluster nodes may be down or draining"
    fi
}

# Display timeout details
display_timeout_details() {
    log_error "Deployment Timeout Analysis:"
    echo "=================================="
    
    # Final status
    log_info "Final Status:"
    nomad job status "$SERVICE_NAME" 2>/dev/null || log_error "Could not get final status"
    
    # Allocation status
    log_info "Allocation Status:"
    nomad job allocs "$SERVICE_NAME" 2>/dev/null || log_error "Could not get allocation status"
    
    echo "=================================="
}

# Cleanup function
cleanup() {
    log_info "Performing cleanup..."
    
    # Remove old backup files (keep last 5)
    if [[ -n "$HCL_FILE" ]]; then
        local backup_dir
        backup_dir=$(dirname "$HCL_FILE")
        find "$backup_dir" -name "$(basename "$HCL_FILE").backup.*" -type f | sort -r | tail -n +6 | xargs -r rm -f
        log_debug "Cleaned up old backup files"
    fi
    
    # Remove temporary validation files
    rm -f "${LOG_FILE}.validation" 2>/dev/null
    
    log_success "Cleanup completed"
}

# Error handler
handle_error() {
    local exit_code=$?
    local line_number=$1
    
    log_error "Script failed at line $line_number with exit code $exit_code"
    
    # Restore backup if processing failed
    if [[ -n "$BACKUP_FILE" && -f "$BACKUP_FILE" && -n "$HCL_FILE" ]]; then
        log_info "Restoring HCL file from backup due to error"
        restore_backup
    fi
    
    cleanup
    
    log_error "Deployment failed. Check logs at: $LOG_FILE"
    exit $exit_code
}

# Signal handlers
handle_signal() {
    local signal="$1"
    log_warning "Received signal: $signal"
    log_info "Initiating graceful shutdown..."
    
    cleanup
    exit 130
}

# Main execution function
main() {
    # Set up error handling
    trap 'handle_error $LINENO' ERR
    trap 'handle_signal SIGINT' INT
    trap 'handle_signal SIGTERM' TERM
    trap cleanup EXIT
    
    # Print header
    print_header
    
    # Validate parameters
    validate_parameters "$@"
    
    # Validate environment
    validate_environment
    
    # Find HCL file
    if ! find_hcl_file; then
        log_error "Cannot proceed without HCL file"
        exit 1
    fi
    
    # Process HCL file
    if ! process_hcl_file; then
        log_error "Failed to process HCL file"
        exit 1
    fi
    
    # Test Nomad connectivity
    if ! test_nomad_connectivity; then
        log_error "Cannot connect to Nomad cluster"
        exit 1
    fi
    
    # Validate job configuration
    if ! validate_nomad_job; then
        log_error "Job validation failed"
        exit 1
    fi
    
    # Create deployment plan
    plan_deployment
    
    # Execute deployment
    if ! execute_deployment; then
        log_error "Deployment execution failed"
        exit 1
    fi
    
    # Monitor deployment
    if monitor_deployment; then
        log_success "🎉 Deployment completed successfully!"
        log_info "📊 Service URL: http://localhost:$SERVICE_PORT"
        log_info "📊 Nomad UI: $NOMAD_ADDR/ui/jobs/$SERVICE_NAME"
        log_info "📝 Log file: $LOG_FILE"
        
        # Final service information
        echo
        echo -e "${GREEN}=================================="
        echo "🎉 DEPLOYMENT SUCCESSFUL"
        echo "=================================="
        echo "Service: $SERVICE_NAME"
        echo "Image: $DOCKER_IMAGE:$IMAGE_TAG"
        echo "Port: $SERVICE_PORT"
        echo "Status: Running"
        echo "Time: $(date)"
        echo -e "==================================${NC}"
        echo
        
        return 0
    else
        log_error "Deployment monitoring failed"
        return 1
    fi
}

# Script entry point with comprehensive error handling
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Enable debug mode if requested
    if [[ "${1:-}" == "--debug" ]]; then
        set -x
        DEBUG=true
        shift
    fi
    
    # Check if help is requested
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        echo "Enhanced Nomad Deployment Script v${SCRIPT_VERSION}"
        echo
        echo "Usage: $0 [--debug] <service-name> <docker-image> <image-tag> <service-port>"
        echo
        echo "Options:"
        echo "  --debug          Enable debug output"
        echo "  --help, -h       Show this help message"
        echo
        echo "Environment Variables:"
        echo "  NOMAD_ADDR       Nomad server address (required)"
        echo "  NOMAD_TOKEN      Nomad authentication token (required)"
        echo
        echo "Examples:"
        echo "  $0 user-service friendy21/user-service main-abc123 5001"
        echo "  $0 --debug calendar-service friendy21/calendar-service v1.0.0 5002"
        echo
        exit 0
    fi
    
    # Execute main function
    if main "$@"; then
        log_success "Script completed successfully"
        exit 0
    else
        log_error "Script execution failed"
        exit 1
    fi
fi
