#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# setup-aws-gov.sh — Configure AWS CLI for GovCloud and verify access
#
# Usage:
#   source ./scripts/setup-aws-gov.sh
#   source ./scripts/setup-aws-gov.sh --profile my-profile
# -----------------------------------------------------------------------------
set -euo pipefail

PROFILE_NAME="${2:-f5xc-aws-govcloud}"
REGION="us-gov-west-1"

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE_NAME="$2"; shift 2 ;;
    *) shift ;;
  esac
done

echo "=== AWS GovCloud Setup ==="
echo "Profile: $PROFILE_NAME"
echo "Region:  $REGION"
echo ""

# Check if AWS CLI is installed
if ! command -v aws &>/dev/null; then
  echo "ERROR: AWS CLI is not installed. Install from https://aws.amazon.com/cli/"
  return 1 2>/dev/null || exit 1
fi

# Check if profile already exists and works
echo "Checking existing profile..."
if aws sts get-caller-identity --profile "$PROFILE_NAME" --region "$REGION" &>/dev/null; then
  IDENTITY=$(aws sts get-caller-identity --profile "$PROFILE_NAME" --region "$REGION" --output json)
  echo "Profile '$PROFILE_NAME' is active:"
  echo "  Account: $(echo "$IDENTITY" | jq -r .Account)"
  echo "  ARN:     $(echo "$IDENTITY" | jq -r .Arn)"
  echo ""
else
  echo "Profile '$PROFILE_NAME' not configured or credentials expired."
  echo ""
  echo "To configure SSO-based access:"
  echo "  aws configure sso --profile $PROFILE_NAME"
  echo ""
  echo "To configure static credentials:"
  echo "  aws configure --profile $PROFILE_NAME"
  echo "  aws configure set profile.$PROFILE_NAME.region $REGION"
  echo ""
  echo "For temporary STS credentials from IAM Identity Center:"
  echo "  aws configure set profile.$PROFILE_NAME.aws_access_key_id <KEY>"
  echo "  aws configure set profile.$PROFILE_NAME.aws_secret_access_key <SECRET>"
  echo "  aws configure set profile.$PROFILE_NAME.aws_session_token <TOKEN>"
  echo "  aws configure set profile.$PROFILE_NAME.region $REGION"
  echo ""
  return 1 2>/dev/null || exit 1
fi

# Export for Terraform
export AWS_PROFILE="$PROFILE_NAME"
export AWS_REGION="$REGION"

echo "Exported environment:"
echo "  AWS_PROFILE=$AWS_PROFILE"
echo "  AWS_REGION=$AWS_REGION"
echo ""

# Remind about F5 XC credentials
echo "Don't forget to set the F5 XC API password:"
echo "  export VES_P12_PASSWORD=\"your-p12-password\""
echo ""
echo "Then run:"
echo "  terraform init"
echo "  terraform plan"
