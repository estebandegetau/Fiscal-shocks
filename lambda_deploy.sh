#!/bin/bash
# AWS Lambda Container Deployment Script for Fiscal Shocks PDF Extraction
#
# This script packages the Docling PDF extractor as an AWS Lambda container image
# and deploys it via ECR (Elastic Container Registry).
#
# Prerequisites:
# - AWS CLI configured with credentials
# - Docker Desktop running (for building container images)
# - Sufficient IAM permissions for ECR, Lambda, IAM, and S3
#
# Usage:
#   ./lambda_deploy.sh [--function-name NAME] [--region REGION] [--bucket BUCKET]

set -e  # Exit on error

# Load .env file if it exists
if [ -f .env ]; then
  echo "Loading environment variables from .env file..."
  set -a  # Automatically export all variables
  source <(grep -v '^#' .env | grep -v '^$')
  set +a
fi

# Default configuration
FUNCTION_NAME="${LAMBDA_FUNCTION_NAME:-fiscal-shocks-pdf-extractor}"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
S3_BUCKET="${AWS_S3_BUCKET:-fiscal-shocks-pdfs}"
MEMORY_SIZE=3008  # MB (3GB)
TIMEOUT=900  # seconds (15 minutes) - large PDFs need more processing time
ECR_REPO="$FUNCTION_NAME"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --function-name)
      FUNCTION_NAME="$2"
      ECR_REPO="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --bucket)
      S3_BUCKET="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--function-name NAME] [--region REGION] [--bucket BUCKET]"
      exit 1
      ;;
  esac
done

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO}"

echo "========================================="
echo "AWS Lambda Container Deployment"
echo "========================================="
echo "Function Name: $FUNCTION_NAME"
echo "Region: $REGION"
echo "S3 Bucket: $S3_BUCKET"
echo "ECR URI: $ECR_URI"
echo "Memory: ${MEMORY_SIZE}MB"
echo "Timeout: ${TIMEOUT}s"
echo ""

# Step 1: Create S3 bucket if it doesn't exist
echo "[1/6] Checking S3 bucket..."
if aws s3 ls "s3://$S3_BUCKET" 2>/dev/null; then
  echo "  ✓ Bucket $S3_BUCKET exists"
else
  echo "  Creating S3 bucket $S3_BUCKET..."
  if [ "$REGION" = "us-east-1" ]; then
    aws s3 mb "s3://$S3_BUCKET" --region "$REGION"
  else
    aws s3 mb "s3://$S3_BUCKET" --region "$REGION" --create-bucket-configuration LocationConstraint="$REGION"
  fi
  echo "  ✓ Bucket created"
fi

# Step 2: Create ECR repository if it doesn't exist
echo ""
echo "[2/6] Creating ECR repository..."
if aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$REGION" >/dev/null 2>&1; then
  echo "  ✓ Repository $ECR_REPO exists"
else
  aws ecr create-repository \
    --repository-name "$ECR_REPO" \
    --image-scanning-configuration scanOnPush=true \
    --region "$REGION" \
    --query 'repository.repositoryUri' \
    --output text

  # Add lifecycle policy to keep only 5 untagged images
  aws ecr put-lifecycle-policy \
    --repository-name "$ECR_REPO" \
    --lifecycle-policy-text '{
      "rules": [{
        "rulePriority": 1,
        "description": "Keep only 5 untagged images",
        "selection": {
          "tagStatus": "untagged",
          "countType": "imageCountMoreThan",
          "countNumber": 5
        },
        "action": {"type": "expire"}
      }]
    }' \
    --region "$REGION" >/dev/null

  echo "  ✓ Repository created with lifecycle policy"
fi

# Step 3: Authenticate Docker to ECR
echo ""
echo "[3/6] Authenticating Docker to ECR..."
aws ecr get-login-password --region "$REGION" | \
  docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
echo "  ✓ Docker authenticated"

# Step 4: Build container image
echo ""
echo "[4/6] Building container image..."
echo "  This may take 5-10 minutes (downloading PyTorch + Docling)..."
# Force linux/amd64 platform for Lambda compatibility (required even on ARM Macs)
# --provenance=false disables BuildKit attestations that create OCI index manifests
# Lambda requires simple Docker v2 schema manifests, not OCI image indexes
docker build --platform linux/amd64 --provenance=false -t "$ECR_REPO:latest" -f Dockerfile.lambda .
echo "  ✓ Container image built"

# Step 5: Tag and push to ECR
echo ""
echo "[5/6] Pushing image to ECR..."
docker tag "$ECR_REPO:latest" "$ECR_URI:latest"
docker push "$ECR_URI:latest"

IMAGE_DIGEST=$(aws ecr describe-images \
  --repository-name "$ECR_REPO" \
  --image-ids imageTag=latest \
  --query 'imageDetails[0].imageDigest' \
  --output text \
  --region "$REGION")
echo "  ✓ Image pushed: $ECR_URI@$IMAGE_DIGEST"

# Step 6: Create or update Lambda function
echo ""
echo "[6/6] Deploying Lambda function..."

# Check if function exists
if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo "  Updating existing function..."

  # Update function code
  aws lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --image-uri "$ECR_URI:latest" \
    --region "$REGION" \
    --query 'FunctionArn' \
    --output text >/dev/null

  # Wait for update to complete
  echo "  Waiting for function update..."
  aws lambda wait function-updated --function-name "$FUNCTION_NAME" --region "$REGION"

  # Update configuration
  aws lambda update-function-configuration \
    --function-name "$FUNCTION_NAME" \
    --memory-size "$MEMORY_SIZE" \
    --timeout "$TIMEOUT" \
    --environment "Variables={S3_BUCKET=$S3_BUCKET}" \
    --region "$REGION" \
    --query 'FunctionArn' \
    --output text >/dev/null

  echo "  ✓ Function updated"
else
  echo "  Creating new function..."

  # Get or create IAM role for Lambda
  ROLE_NAME="${FUNCTION_NAME}-role"

  if ! aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
    echo "  Creating IAM role..."

    # Create trust policy
    TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)

    aws iam create-role \
      --role-name "$ROLE_NAME" \
      --assume-role-policy-document "$TRUST_POLICY" \
      --query 'Role.Arn' \
      --output text >/dev/null

    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
      --role-name "$ROLE_NAME" \
      --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

    # Attach S3 access policy
    S3_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject"
      ],
      "Resource": "arn:aws:s3:::${S3_BUCKET}/*"
    }
  ]
}
EOF
)

    aws iam put-role-policy \
      --role-name "$ROLE_NAME" \
      --policy-name "${ROLE_NAME}-s3-policy" \
      --policy-document "$S3_POLICY"

    echo "  ✓ IAM role created"

    # Wait for role to be available
    echo "  Waiting for IAM role to propagate..."
    sleep 10
  fi

  ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)

  # Create function with container image
  aws lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --package-type Image \
    --code ImageUri="$ECR_URI:latest" \
    --role "$ROLE_ARN" \
    --memory-size "$MEMORY_SIZE" \
    --timeout "$TIMEOUT" \
    --environment "Variables={S3_BUCKET=$S3_BUCKET}" \
    --region "$REGION" \
    --query 'FunctionArn' \
    --output text >/dev/null

  echo "  ✓ Function created"
fi

# Summary
echo ""
echo "========================================="
echo "✓ Deployment Complete!"
echo "========================================="
echo ""
echo "Function ARN: arn:aws:lambda:${REGION}:${AWS_ACCOUNT_ID}:function:${FUNCTION_NAME}"
echo "Image URI: $ECR_URI:latest"
echo "S3 Bucket: s3://$S3_BUCKET"
echo ""
echo "Test the function:"
echo "  aws lambda invoke --function-name $FUNCTION_NAME \\"
echo "    --payload '{\"pdf_url\":\"https://www.govinfo.gov/content/pkg/ERP-2024/pdf/ERP-2024.pdf\",\"output_key\":\"test/erp-2024.json\"}' \\"
echo "    --region $REGION response.json"
echo ""
echo "Test from R:"
echo "  Rscript -e 'source(\"R/pull_text_lambda.R\"); pull_text_lambda(\"<pdf_url>\")'"
echo ""
