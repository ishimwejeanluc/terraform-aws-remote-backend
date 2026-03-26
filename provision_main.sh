#!/bin/bash
#
# provision_main.sh
#
# This script automates the provisioning of the main Terraform infrastructure.
# It initializes Terraform with the remote backend, validates the configuration,
# and applies the changes.
#
# The script is designed to be idempotent and follows DevOps best practices.

# --- Configuration ---
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Return the exit status of the last command in the pipe that failed.

# --- Logging ---
# Log color constants
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

# --- Functions ---

# Function to check for required command-line tools
validate_dependencies() {
    log_info "Validating dependencies..."
    local dependencies=("terraform" "aws" "grep" "terraform")
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "'$cmd' command not found. Please install it and ensure it's in your PATH."
        fi
    done
    log_success "All dependencies are installed."
}

# Function to verify AWS user identity
validate_aws_identity() {
    log_info "Validating AWS identity..."
    if ! aws_identity=$(aws sts get-caller-identity --output json); then
        log_error "Failed to get AWS caller identity. Please configure your AWS credentials."
    fi
    local user_arn
    user_arn=$(echo "$aws_identity" | jq -r '.Arn')
    log_success "Running as AWS identity: $user_arn"
}

# Function to validate required AWS permissions for main resources
validate_main_permissions() {
    log_info "Validating AWS permissions for main resources..."
    local user_arn
    user_arn=$(aws sts get-caller-identity --query Arn --output text)
    if [[ -z "$user_arn" ]]; then
        log_error "Could not determine AWS user ARN."
    fi

    # Permissions derived from main.tf resources
    local required_permissions=(
        "ec2:DescribeImages"
        "ec2:CreateVpc"
        "ec2:CreateTags"
        "ec2:CreateSubnet"
        "ec2:CreateInternetGateway"
        "ec2:AttachInternetGateway"
        "ec2:CreateRouteTable"
        "ec2:CreateRoute"
        "ec2:AssociateRouteTable"
        "ec2:CreateSecurityGroup"
        "ec2:AuthorizeSecurityGroupIngress"
        "ec2:RunInstances"
    )

    log_info "Simulating IAM policy for required EC2 permissions..."
    simulation_output=$(aws iam simulate-principal-policy \
        --policy-source-arn "$user_arn" \
        --action-names "${required_permissions[@]}" \
        --output json)

    local all_allowed=true
    for result in $(echo "$simulation_output" | jq -c '.EvaluationResults[]'); do
        decision=$(echo "$result" | jq -r '.EvalDecision')
        action=$(echo "$result" | jq -r '.EvalActionName')
        if [[ "$decision" != "allowed" ]]; then
            all_allowed=false
            log_warning "Permission check failed for action: $action. Decision: $decision"
        fi
    done

    if [[ "$all_allowed" == "false" ]]; then
        log_error "One or more required AWS permissions are missing. Please check the IAM policy for $user_arn."
    fi

    log_success "AWS permissions for main resources validated successfully."
}


# Function to validate that the backend.hcl file is configured
validate_backend_config() {
    log_info "Validating backend.hcl configuration..."
    if [[ ! -f "backend.hcl" ]]; then
        log_error "backend.hcl not found. Please run the ./initialize_backend.sh script first."
    fi

    if grep -q "REPLACE_ME" "backend.hcl"; then
        log_error "backend.hcl contains placeholder values. Please run ./initialize_backend.sh to configure it."
    fi
    log_success "backend.hcl is configured."
}

# Function to provision the main infrastructure
provision_main_infrastructure() {
    log_info "Provisioning main Terraform infrastructure..."

    log_info "Running 'terraform init'..."
    if ! terraform init -reconfigure -backend-config=backend.hcl; then
        log_error "Terraform init failed. Check backend configuration and AWS credentials."
    fi

    log_info "Running 'terraform validate'..."
    if ! terraform validate; then
        log_error "Terraform validation failed. Please check your .tf files for errors."
    fi

    log_info "Running 'terraform apply'..."
    if ! terraform apply -auto-approve; then
        log_error "Terraform apply failed. Check permissions and resource configurations."
    fi

    log_success "Main infrastructure provisioned successfully."
}

# --- Main Execution ---

main() {
    log_info "Starting main infrastructure provisioning script."
    
    validate_dependencies
    validate_aws_identity
    validate_backend_config
    validate_main_permissions
    provision_main_infrastructure

    log_success "Main provisioning complete."
}

main
