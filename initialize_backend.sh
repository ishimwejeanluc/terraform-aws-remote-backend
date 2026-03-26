#!/bin/bash
#
# initialize_backend.sh
#
# Automates Terraform backend initialization:
# - Validates dependencies
# - Checks AWS identity
# - Simulates required AWS permissions safely
# - Provisions backend (S3 + DynamoDB)
# - Updates backend.hcl with outputs
#
# Idempotent and designed for CI/CD best practices

set -e
set -o pipefail

# --- Logging ---
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }

# --- Functions ---

validate_dependencies() {
    log_info "Validating dependencies..."
    local deps=("terraform" "aws" "jq")
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "'$cmd' command not found. Please install it and ensure it's in your PATH."
        fi
    done
    log_success "All dependencies are installed."
}

validate_aws_identity() {
    log_info "Validating AWS identity..."
    if ! aws_identity=$(aws sts get-caller-identity --output json); then
        log_error "Failed to get AWS caller identity. Check AWS credentials."
    fi
    user_arn=$(echo "$aws_identity" | jq -r '.Arn')
    log_success "Running as AWS identity: $user_arn"
}

validate_aws_permissions() {
    log_info "Validating AWS permissions..."
    local user_arn
    user_arn=$(aws sts get-caller-identity --query Arn --output text)
    [[ -z "$user_arn" ]] && log_error "Could not determine AWS user ARN."

    local required_permissions=(
        "s3:CreateBucket"
        "s3:PutBucketVersioning"
        "s3:PutEncryptionConfiguration"
        "s3:PutBucketTagging"
        "dynamodb:CreateTable"
        "dynamodb:DescribeTable"
        "dynamodb:TagResource"
    )

    # Attempt simulation safely
    if ! simulation_output=$(aws iam simulate-principal-policy \
        --policy-source-arn "$user_arn" \
        --action-names "${required_permissions[@]}" \
        --output json 2>/dev/null); then
        log_warning "Skipping IAM permission simulation (insufficient 'iam:SimulatePrincipalPolicy' permissions)."
        return
    fi

    # Validate JSON
    if ! echo "$simulation_output" | jq empty >/dev/null 2>&1; then
        log_error "Invalid JSON received from AWS CLI. Check permissions or AWS CLI configuration."
    fi

    # Iterate safely over results
    local all_allowed=true
    while read -r result; do
        decision=$(echo "$result" | jq -r '.EvalDecision')
        action=$(echo "$result" | jq -r '.EvalActionName')

        if [[ "$decision" != "allowed" ]]; then
            all_allowed=false
            log_warning "Permission denied for action: $action"
        fi
    done < <(echo "$simulation_output" | jq -c '.EvaluationResults[]')

    [[ "$all_allowed" == "false" ]] && log_error "One or more required AWS permissions are missing."
    log_success "AWS permissions validated successfully."
}

provision_backend() {
    log_info "Provisioning Terraform backend resources..."
    pushd backend-bootstrap >/dev/null || log_error "Cannot enter backend-bootstrap directory."

    if ! terraform init; then
        log_error "Terraform init failed in backend-bootstrap."
    fi

    if ! terraform apply -auto-approve; then
        log_error "Terraform apply failed in backend-bootstrap. Check permissions and configuration."
    fi

    log_success "Backend infrastructure provisioned successfully."
    popd >/dev/null
}

update_backend_config() {
    log_info "Updating backend.hcl configuration..."
    local state_bucket lock_table
    state_bucket=$(cd backend-bootstrap && terraform output -raw state_bucket_name)
    lock_table=$(cd backend-bootstrap && terraform output -raw lock_table_name)

    [[ -z "$state_bucket" || -z "$lock_table" ]] && log_error "Failed to retrieve Terraform outputs."

    # Cross-platform sed
    local sed_arg="-i"
    [[ "$(uname)" == "Darwin" ]] && sed_arg="-i ''"

    sed $sed_arg "s/REPLACE_ME_TF_STATE_BUCKET/$state_bucket/" backend.hcl
    sed $sed_arg "s/REPLACE_ME_TF_LOCK_TABLE/$lock_table/" backend.hcl

    log_success "backend.hcl updated with bucket '$state_bucket' and table '$lock_table'."
}

# --- Main ---

main() {
    log_info "Starting Terraform backend initialization script."

    validate_dependencies
    validate_aws_identity
    validate_aws_permissions
    provision_backend
    update_backend_config

    log_success "Backend initialization complete. You can now run 'terraform init' in the root directory."
}

main