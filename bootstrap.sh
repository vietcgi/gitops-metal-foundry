#!/usr/bin/env bash
#
# GitOps Metal Foundry - Bootstrap Script
#
# This script sets up OCI credentials for GitHub Actions OIDC authentication.
# Terraform runs from GitHub Actions, not from this script.
#
# Run from OCI Cloud Shell:
#   curl -sSL https://raw.githubusercontent.com/YOUR_USER/gitops-metal-foundry/main/bootstrap.sh | bash
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Logging
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

banner() {
    echo -e "${CYAN}"
    cat << 'EOF'

   ╔═══════════════════════════════════════════════════════════════════╗
   ║                                                                   ║
   ║   ██████╗ ██╗████████╗ ██████╗ ██████╗ ███████╗                  ║
   ║  ██╔════╝ ██║╚══██╔══╝██╔═══██╗██╔══██╗██╔════╝                  ║
   ║  ██║  ███╗██║   ██║   ██║   ██║██████╔╝███████╗                  ║
   ║  ██║   ██║██║   ██║   ██║   ██║██╔═══╝ ╚════██║                  ║
   ║  ╚██████╔╝██║   ██║   ╚██████╔╝██║     ███████║                  ║
   ║   ╚═════╝ ╚═╝   ╚═╝    ╚═════╝ ╚═╝     ╚══════╝                  ║
   ║                                                                   ║
   ║   ███╗   ███╗███████╗████████╗ █████╗ ██╗                        ║
   ║   ████╗ ████║██╔════╝╚══██╔══╝██╔══██╗██║                        ║
   ║   ██╔████╔██║█████╗     ██║   ███████║██║                        ║
   ║   ██║╚██╔╝██║██╔══╝     ██║   ██╔══██║██║                        ║
   ║   ██║ ╚═╝ ██║███████╗   ██║   ██║  ██║███████╗                   ║
   ║   ╚═╝     ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝                   ║
   ║                                                                   ║
   ║   ███████╗ ██████╗ ██╗   ██╗███╗   ██╗██████╗ ██████╗ ██╗   ██╗  ║
   ║   ██╔════╝██╔═══██╗██║   ██║████╗  ██║██╔══██╗██╔══██╗╚██╗ ██╔╝  ║
   ║   █████╗  ██║   ██║██║   ██║██╔██╗ ██║██║  ██║██████╔╝ ╚████╔╝   ║
   ║   ██╔══╝  ██║   ██║██║   ██║██║╚██╗██║██║  ██║██╔══██╗  ╚██╔╝    ║
   ║   ██║     ╚██████╔╝╚██████╔╝██║ ╚████║██████╔╝██║  ██║   ██║     ║
   ║   ╚═╝      ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝╚═════╝ ╚═╝  ╚═╝   ╚═╝     ║
   ║                                                                   ║
   ╚═══════════════════════════════════════════════════════════════════╝

EOF
    echo -e "${NC}"
    echo -e "   ${BOLD}Bare Metal Cloud on Oracle Free Tier${NC}"
    echo -e "   ${BOLD}Powered by: Tinkerbell + K3s + Cilium + Flux${NC}"
    echo ""
    echo -e "   ${GREEN}Cost: \$0.00/month (Always Free Tier)${NC}"
    echo ""
}

#=============================================================================
# Step 1: Validate OCI Environment
#=============================================================================

validate_oci() {
    log_info "Validating OCI environment..."

    # Check if running in Cloud Shell
    if [[ -n "${OCI_CLI_CLOUD_SHELL:-}" ]]; then
        log_success "Running in OCI Cloud Shell"
    else
        log_warn "Not in Cloud Shell - ensure OCI CLI is configured"
    fi

    # Check required tools
    for cmd in oci jq curl; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Missing required tool: $cmd"
            exit 1
        fi
    done

    # Verify OCI authentication
    if ! oci iam region list --output table &> /dev/null; then
        log_error "OCI authentication failed"
        exit 1
    fi
    log_success "OCI authentication verified"

    # Get tenancy OCID
    if [[ -n "${OCI_TENANCY:-}" ]]; then
        :
    elif [[ -n "${OCI_CLI_TENANCY:-}" ]]; then
        OCI_TENANCY="$OCI_CLI_TENANCY"
    else
        OCI_TENANCY=$(grep '^tenancy' ~/.oci/config 2>/dev/null | head -1 | cut -d'=' -f2 | tr -d ' ')
    fi

    if [[ -z "$OCI_TENANCY" ]]; then
        log_info "Detecting tenancy from API..."
        OCI_TENANCY=$(oci iam user list --limit 1 --query 'data[0]."compartment-id"' --raw-output 2>/dev/null)
    fi

    if [[ -z "$OCI_TENANCY" ]]; then
        log_error "Could not determine tenancy OCID"
        exit 1
    fi

    log_info "Tenancy: ${OCI_TENANCY:0:50}..."
    export OCI_TENANCY
}

#=============================================================================
# Step 2: Get Configuration
#=============================================================================

get_config() {
    echo ""
    log_info "Configuration"
    echo ""

    # Region
    if [[ -n "${OCI_CLI_REGION:-}" ]]; then
        OCI_REGION="$OCI_CLI_REGION"
        log_info "Using Cloud Shell region: $OCI_REGION"
    else
        read -r -p "Enter OCI region (e.g., us-sanjose-1): " OCI_REGION < /dev/tty
    fi
    export OCI_REGION

    # GitHub repo
    echo ""
    log_info "GitHub repository for GitOps (e.g., vietcgi/gitops-metal-foundry)"
    read -r -p "Enter GitHub owner/repo: " GITHUB_REPO_FULL < /dev/tty

    if [[ -z "$GITHUB_REPO_FULL" ]]; then
        log_error "GitHub repo is required for GitOps"
        exit 1
    fi

    GITHUB_OWNER=$(echo "$GITHUB_REPO_FULL" | cut -d'/' -f1)
    GITHUB_REPO=$(echo "$GITHUB_REPO_FULL" | cut -d'/' -f2)

    log_info "GitHub Owner: $GITHUB_OWNER"
    log_info "GitHub Repo: $GITHUB_REPO"

    # Project name
    PROJECT_NAME="${PROJECT_NAME:-metal-foundry}"
}

#=============================================================================
# Step 3: Create Compartment
#=============================================================================

create_compartment() {
    log_info "Setting up OCI compartment..."

    EXISTING=$(oci iam compartment list \
        --query "data[?name=='${PROJECT_NAME}' && \"lifecycle-state\"=='ACTIVE'].id | [0]" \
        --raw-output 2>/dev/null || echo "")

    if [[ -n "$EXISTING" && "$EXISTING" != "null" ]]; then
        log_info "Using existing compartment: $PROJECT_NAME"
        OCI_COMPARTMENT="$EXISTING"
    else
        log_info "Creating compartment: $PROJECT_NAME"
        OCI_COMPARTMENT=$(oci iam compartment create \
            --compartment-id "$OCI_TENANCY" \
            --name "$PROJECT_NAME" \
            --description "GitOps Metal Foundry - Bare Metal Cloud" \
            --wait-for-state ACTIVE \
            --query 'data.id' \
            --raw-output 2>/dev/null) || {
            log_warn "Could not create compartment, using tenancy root"
            OCI_COMPARTMENT="$OCI_TENANCY"
        }
    fi

    log_success "Compartment: ${OCI_COMPARTMENT:0:50}..."
    export OCI_COMPARTMENT
}

#=============================================================================
# Step 4: Get SSH Public Key
#=============================================================================

get_ssh_key() {
    log_info "SSH public key for VM access"
    echo ""

    # Check for existing keys
    if [[ -f ~/.ssh/id_rsa.pub ]]; then
        log_info "Found existing key: ~/.ssh/id_rsa.pub"
        read -r -p "Use this key? (y/n): " use_existing < /dev/tty
        if [[ "$use_existing" =~ ^[Yy]$ ]]; then
            SSH_PUBLIC_KEY=$(cat ~/.ssh/id_rsa.pub)
            export SSH_PUBLIC_KEY
            return
        fi
    fi

    echo "Paste your SSH public key (or press Enter to skip):"
    read -r SSH_PUBLIC_KEY < /dev/tty

    if [[ -z "$SSH_PUBLIC_KEY" ]]; then
        log_warn "No SSH key provided - you'll need to add it to GitHub secrets as SSH_PUBLIC_KEY"
        SSH_PUBLIC_KEY=""
    fi
    export SSH_PUBLIC_KEY
}

#=============================================================================
# Step 5: Setup GitHub OIDC in OCI
#=============================================================================

setup_oidc() {
    log_info "Setting up GitHub OIDC authentication..."

    # Check if dynamic group exists
    DG_NAME="${PROJECT_NAME}-github-actions"
    EXISTING_DG=$(oci iam dynamic-group list \
        --compartment-id "$OCI_TENANCY" \
        --query "data[?name=='${DG_NAME}'].id | [0]" \
        --raw-output 2>/dev/null || echo "")

    if [[ -n "$EXISTING_DG" && "$EXISTING_DG" != "null" ]]; then
        log_info "Dynamic group already exists: $DG_NAME"
    else
        log_info "Creating dynamic group for GitHub Actions..."

        # Matching rule for GitHub OIDC
        MATCHING_RULE="All {resource.type='github-actions-oidc', resource.repository='${GITHUB_OWNER}/${GITHUB_REPO}'}"

        oci iam dynamic-group create \
            --compartment-id "$OCI_TENANCY" \
            --name "$DG_NAME" \
            --description "GitHub Actions OIDC for ${GITHUB_OWNER}/${GITHUB_REPO}" \
            --matching-rule "$MATCHING_RULE" \
            --wait-for-state ACTIVE > /dev/null 2>&1 || {
            log_warn "Could not create dynamic group (may need admin privileges)"
        }
    fi

    # Check if policy exists
    POLICY_NAME="${PROJECT_NAME}-github-actions-policy"
    EXISTING_POLICY=$(oci iam policy list \
        --compartment-id "$OCI_TENANCY" \
        --query "data[?name=='${POLICY_NAME}'].id | [0]" \
        --raw-output 2>/dev/null || echo "")

    if [[ -n "$EXISTING_POLICY" && "$EXISTING_POLICY" != "null" ]]; then
        log_info "Policy already exists: $POLICY_NAME"
    else
        log_info "Creating IAM policy for GitHub Actions..."

        STATEMENTS='["Allow dynamic-group '"${DG_NAME}"' to manage all-resources in compartment '"${PROJECT_NAME}"'"]'

        oci iam policy create \
            --compartment-id "$OCI_TENANCY" \
            --name "$POLICY_NAME" \
            --description "Permissions for GitHub Actions to manage Metal Foundry resources" \
            --statements "$STATEMENTS" > /dev/null 2>&1 || {
            log_warn "Could not create policy (may need admin privileges)"
        }
    fi

    log_success "OIDC setup complete"
}

#=============================================================================
# Step 6: Print GitHub Setup Instructions
#=============================================================================

print_github_instructions() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}${BOLD}  Bootstrap Complete!${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BOLD}Step 1: Add these Repository Variables to GitHub${NC}"
    echo ""
    echo "  Go to: https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/settings/variables/actions"
    echo ""
    echo "  ┌─────────────────────┬─────────────────────────────────────────────────┐"
    echo "  │ Variable Name       │ Value                                           │"
    echo "  ├─────────────────────┼─────────────────────────────────────────────────┤"
    printf "  │ %-19s │ %-47s │\n" "OCI_TENANCY" "${OCI_TENANCY:0:47}"
    printf "  │ %-19s │ %-47s │\n" "OCI_COMPARTMENT" "${OCI_COMPARTMENT:0:47}"
    printf "  │ %-19s │ %-47s │\n" "OCI_REGION" "$OCI_REGION"
    echo "  └─────────────────────┴─────────────────────────────────────────────────┘"
    echo ""
    if [[ -n "$SSH_PUBLIC_KEY" ]]; then
        echo -e "${BOLD}Step 2: Add SSH Public Key as Repository Secret${NC}"
        echo ""
        echo "  Go to: https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/settings/secrets/actions"
        echo ""
        echo "  Secret Name: SSH_PUBLIC_KEY"
        echo "  Value:"
        echo "$SSH_PUBLIC_KEY"
        echo ""
    else
        echo -e "${BOLD}Step 2: Add SSH Public Key as Repository Secret${NC}"
        echo ""
        echo "  Go to: https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/settings/secrets/actions"
        echo "  Add secret: SSH_PUBLIC_KEY = (your public key)"
        echo ""
    fi
    echo -e "${BOLD}Step 3: Trigger Infrastructure Creation${NC}"
    echo ""
    echo "  Option A: Push a change to terraform/ directory"
    echo "  Option B: Go to Actions tab and manually run 'Terraform' workflow"
    echo ""
    echo "  The workflow will:"
    echo "    - On PR: Run 'terraform plan' and comment the changes"
    echo "    - On merge to main: Run 'terraform apply' to create infrastructure"
    echo ""
    echo -e "${BOLD}Step 4: After Infrastructure is Created${NC}"
    echo ""
    echo "  1. Get the control plane IP from Terraform output"
    echo "  2. SSH to the VM: ssh -i ~/.ssh/metal-foundry ubuntu@<IP>"
    echo "  3. Run the control plane setup script"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Cost: \$0.00/month (Oracle Always Free Tier)${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

#=============================================================================
# Main
#=============================================================================

main() {
    banner
    validate_oci
    get_config
    create_compartment
    get_ssh_key
    setup_oidc
    print_github_instructions
}

# Handle errors
trap 'log_error "Bootstrap failed at line $LINENO"' ERR

main "$@"
