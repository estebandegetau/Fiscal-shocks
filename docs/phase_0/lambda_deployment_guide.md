# AWS Lambda Deployment Guide for PDF Extraction

## Overview

This guide explains how to deploy and use AWS Lambda for parallel PDF extraction with Docling, replacing the slow laptop-based extraction.

**Performance Improvement:**
- **Before**: 17+ hours for 350 PDFs on laptop (sequential subprocess calls)
- **After**: 5-10 minutes with Lambda (350 parallel invocations)

**Cost**: ~$6 for full extraction (350 PDFs × 4.8 min avg × 3GB × $0.0000166667/GB-second)

---

## Architecture

The Lambda function is deployed as a **container image via Amazon ECR** (Elastic Container Registry). This approach supports images up to 10GB, which is necessary because Docling + PyTorch requires ~4-5GB.

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   R/targets     │────▶│  AWS Lambda     │────▶│   Amazon S3     │
│   pipeline      │     │  (Container)    │     │   (JSON output) │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                               │
                               ▼
                        ┌─────────────────┐
                        │   Amazon ECR    │
                        │   (Docker img)  │
                        └─────────────────┘
```

---

## Prerequisites

### 1. AWS Account Setup

You need an AWS account with:
- IAM permissions to create Lambda functions, ECR repositories, S3 buckets, and IAM roles
- AWS CLI installed and configured

**Install AWS CLI** (if not already installed):
```bash
# macOS
brew install awscli

# Linux
pip install awscli

# Windows
# Download from https://aws.amazon.com/cli/
```

**Configure AWS credentials:**
```bash
aws configure
# Enter your AWS Access Key ID, Secret Access Key, Region, and output format
```

Or create a `.env` file:
```bash
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=xxx...
AWS_DEFAULT_REGION=us-east-1
```

### 2. Docker

Docker is required to build the container image compatible with AWS Lambda's environment.

**Install Docker**:
- macOS/Windows: Download [Docker Desktop](https://www.docker.com/products/docker-desktop)
- Linux: `sudo apt-get install docker.io` or `sudo yum install docker`

**Verify installation:**
```bash
docker --version
```

### 3. R Package Dependencies

Install the following R packages:
```r
install.packages(c("paws.storage", "paws.compute", "furrr", "future"))
```

---

## Deployment Steps

### Step 1: Configure Environment Variables

Create a `.env` file in the project root:

```bash
cp .env.example .env
```

Edit `.env` with your AWS credentials:
```
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=xxx...
AWS_DEFAULT_REGION=us-east-1
```

**Load environment variables in R:**
```r
# In _targets.R or your R script
dotenv::load_dot_env()
```

### Step 2: Run Deployment Script

Deploy the Lambda function as a container image:

```bash
./lambda_deploy.sh
```

**Recommended: Run in tmux session** (survives disconnections):
```bash
tmux new -s lambda
./lambda_deploy.sh
# Detach: Ctrl+b, d
# Reattach: tmux attach -t lambda
```

**What the script does:**
1. Checks/creates S3 bucket for output
2. Creates ECR repository (if it doesn't exist)
3. Authenticates Docker to ECR
4. Builds container image (~5-10 minutes, downloads PyTorch ~2GB)
5. Pushes image to ECR (~3-5 minutes)
6. Creates/updates Lambda function with container image

**Expected output:**
```
=========================================
AWS Lambda Deployment for Fiscal Shocks
=========================================
Function Name: fiscal-shocks-pdf-extractor
Region: us-east-1
S3 Bucket: fiscal-shocks-pdfs
Memory: 3008MB
Timeout: 300s

[1/6] Checking S3 bucket...
  ✓ Bucket fiscal-shocks-pdfs exists

[2/6] Creating ECR repository...
  ✓ ECR repository exists

[3/6] Authenticating Docker to ECR...
  Login Succeeded

[4/6] Building container image...
  Building Dockerfile.lambda (this may take 5-10 minutes)...
  ✓ Image built successfully

[5/6] Pushing image to ECR...
  ✓ Image pushed to ECR

[6/6] Deploying Lambda function...
  ✓ Function created/updated

=========================================
✓ Deployment Complete!
=========================================

Function ARN: arn:aws:lambda:us-east-1:123456789:function:fiscal-shocks-pdf-extractor
ECR Image: 123456789.dkr.ecr.us-east-1.amazonaws.com/fiscal-shocks-pdf-extractor:latest
S3 Bucket: s3://fiscal-shocks-pdfs
```

### Step 3: Verify Deployment

Test the Lambda function:

```bash
aws lambda invoke \
  --function-name fiscal-shocks-pdf-extractor \
  --payload '{"pdf_url":"https://www.irs.gov/pub/irs-pdf/fw4.pdf","output_key":"test/fw4.json"}' \
  response.json && cat response.json
```

Expected output:
```json
{
  "statusCode": 200,
  "body": "{\"pages\": [\"...extracted text...\"], \"n_pages\": 1, \"error\": null, \"s3_key\": \"test/fw4.json\"}"
}
```

---

## Usage

### Option 1: Integrate with Targets Pipeline

**Update `_targets.R`:**

```r
# Load environment variables
dotenv::load_dot_env()

# Replace pull_text_docling with pull_text_lambda
tar_target(
  us_text,
  pull_text_lambda(us_urls_vector),
  pattern = map(us_urls_vector),
  iteration = "vector"
)
```

**Run pipeline:**
```r
tar_make()
```

### Option 2: Standalone R Usage

```r
# Load function
source("R/pull_text_lambda.R")

# Load environment variables
dotenv::load_dot_env()

# Single PDF
result <- pull_text_lambda("https://example.com/document.pdf")

# Multiple PDFs
urls <- c(
  "https://example.com/doc1.pdf",
  "https://example.com/doc2.pdf"
)
results <- purrr::map_dfr(urls, pull_text_lambda)

# View results
results
# A tibble: 2 × 3
#   text       n_pages extracted_at
#   <list>     <int>   <dttm>
# 1 <chr [10]>      10 2025-01-13 15:30:00
# 2 <chr [5]>        5 2025-01-13 15:30:15
```

### Option 3: Local Testing with Docker

Test the container locally before deploying:

```bash
# Build the image
docker build -t fiscal-shocks-pdf-extractor -f Dockerfile.lambda .

# Run locally
docker run -p 9000:8080 fiscal-shocks-pdf-extractor

# Test (in another terminal)
curl -X POST "http://localhost:9000/2015-03-31/functions/function/invocations" \
  -d '{"pdf_url":"https://www.irs.gov/pub/irs-pdf/fw4.pdf","output_key":"test/out.json"}'
```

---

## Configuration Options

### Function Parameters

```r
pull_text_lambda(
  pdf_url,                    # Required: PDF URL(s)
  bucket = "fiscal-shocks-pdfs",
  lambda_function = "fiscal-shocks-pdf-extractor",
  poll_interval = 30,         # Seconds between S3 checks
  max_wait_time = 600,        # Max wait time (10 minutes)
  do_table_structure = TRUE,  # Enable table extraction
  use_parallel = TRUE         # Parallel Lambda invocation
)
```

### Lambda Configuration

The deployment script uses these defaults:
- **Memory**: 3008 MB (3GB)
- **Timeout**: 300 seconds (5 minutes)
- **Runtime**: Python 3.12 (container-based)

**Adjust after deployment:**
```bash
# Increase timeout for large PDFs
aws lambda update-function-configuration \
  --function-name fiscal-shocks-pdf-extractor \
  --timeout 600

# Increase memory if needed
aws lambda update-function-configuration \
  --function-name fiscal-shocks-pdf-extractor \
  --memory-size 5120
```

---

## Monitoring & Debugging

### View Lambda Logs

**AWS Console:**
1. Go to [AWS Lambda Console](https://console.aws.amazon.com/lambda)
2. Click on `fiscal-shocks-pdf-extractor`
3. Go to "Monitor" → "View logs in CloudWatch"

**CLI:**
```bash
aws logs tail /aws/lambda/fiscal-shocks-pdf-extractor --follow
```

### Check S3 Contents

```bash
# List extracted files
aws s3 ls s3://fiscal-shocks-pdfs/extracted/ --recursive

# Download a specific result
aws s3 cp s3://fiscal-shocks-pdfs/extracted/2024/erp/document.json ./
```

### Check ECR Image

```bash
# List images in repository
aws ecr describe-images --repository-name fiscal-shocks-pdf-extractor

# Get image details
aws ecr describe-images --repository-name fiscal-shocks-pdf-extractor \
  --query 'imageDetails[0].{Size:imageSizeInBytes,Pushed:imagePushedAt}'
```

---

## Troubleshooting

### Error: "Read-only file system"

**Cause**: Docling/HuggingFace trying to write to home directory.

**Solution**: The `lambda_handler.py` already sets cache directories to `/tmp`. If you see this error, ensure you're using the latest image:

```bash
# Rebuild and redeploy
./lambda_deploy.sh
```

### Error: "Timeout after 300 seconds"

**Solution**: Some large PDFs (>100 pages) may take longer. Increase timeout:

```bash
aws lambda update-function-configuration \
  --function-name fiscal-shocks-pdf-extractor \
  --timeout 600
```

### Error: "Memory limit exceeded"

**Solution**: Increase Lambda memory:

```bash
aws lambda update-function-configuration \
  --function-name fiscal-shocks-pdf-extractor \
  --memory-size 5120  # 5GB
```

### Error: "retrieval incomplete"

**Cause**: PDF download timed out within Lambda (slow source server).

**Solution**:
1. Retry the request
2. If persistent, download the PDF to S3 first and use S3 URL
3. Consider increasing Lambda timeout

### Error: "Docker push broken pipe"

**Cause**: Network instability during large image push (~4-5GB).

**Solution**: The deployment script has retry logic. If it fails:
```bash
# Re-authenticate and push manually
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/fiscal-shocks-pdf-extractor:latest
```

### Error: "Rate limit exceeded"

**Solution**: Lambda has a default concurrency limit of 1000. If you hit this:

1. Request a limit increase via AWS Support
2. Or batch PDFs into smaller groups:

```r
# Process in batches of 100
urls_batches <- split(us_urls_vector, ceiling(seq_along(us_urls_vector) / 100))

results <- purrr::map_dfr(urls_batches, function(batch) {
  purrr::map_dfr(batch, pull_text_lambda)
  Sys.sleep(60)  # Wait 1 minute between batches
})
```

---

## Cost Estimates

### Container Image Deployment

| Component | Cost |
|-----------|------|
| ECR storage (5GB image) | ~$0.50/month |
| Lambda invocations (350 × 4.8 min × 3GB) | $5.04 |
| S3 storage (350 JSON files, ~100MB total) | $0.002/month |
| CloudWatch logs (2GB) | $1.00 |
| **Total (one-time extraction)** | **~$6** |

### Cold Start Impact

Container images have slightly longer cold starts than zip deployments:
- **Cold start**: ~15-30 seconds
- **Warm invocation**: ~1-5 seconds

For batch processing, most invocations will be warm after the first few.

### Tips to Reduce Costs

1. **Delete S3 files after processing:**
   ```r
   # In R, after tar_read(us_text)
   s3 <- paws.storage::s3()
   s3$delete_objects(
     Bucket = "fiscal-shocks-pdfs",
     Delete = list(Objects = purrr::map(s3_keys, ~ list(Key = .x)))
   )
   ```

2. **Use S3 lifecycle policies** to auto-delete old files:
   ```bash
   aws s3api put-bucket-lifecycle-configuration \
     --bucket fiscal-shocks-pdfs \
     --lifecycle-configuration '{
       "Rules": [{
         "Id": "DeleteAfter7Days",
         "Status": "Enabled",
         "Prefix": "extracted/",
         "Expiration": {"Days": 7}
       }]
     }'
   ```

3. **Reduce Lambda memory** if PDFs are small:
   ```bash
   # Test with 1.5GB instead of 3GB
   aws lambda update-function-configuration \
     --function-name fiscal-shocks-pdf-extractor \
     --memory-size 1536
   ```

---

## Cleanup

To delete all AWS resources:

```bash
# Delete Lambda function
aws lambda delete-function --function-name fiscal-shocks-pdf-extractor

# Delete ECR repository (and all images)
aws ecr delete-repository --repository-name fiscal-shocks-pdf-extractor --force

# Delete IAM role policies
aws iam delete-role-policy --role-name fiscal-shocks-pdf-extractor-role --policy-name fiscal-shocks-pdf-extractor-role-s3-policy
aws iam detach-role-policy --role-name fiscal-shocks-pdf-extractor-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# Delete IAM role
aws iam delete-role --role-name fiscal-shocks-pdf-extractor-role

# Empty and delete S3 bucket
aws s3 rm s3://fiscal-shocks-pdfs --recursive
aws s3 rb s3://fiscal-shocks-pdfs
```

---

## Files Overview

| File | Purpose |
|------|---------|
| `lambda_deploy.sh` | Deployment script (ECR + Lambda) |
| `Dockerfile.lambda` | Container image definition |
| `python/lambda_handler.py` | Lambda handler code |
| `R/pull_text_lambda.R` | R wrapper function |
| `.dockerignore` | Excludes files from Docker build |

---

## Next Steps

After successful deployment:

1. **Test on small subset**: Extract 5-10 PDFs to verify everything works
2. **Full extraction**: Run `tar_make()` to extract all 350 PDFs
3. **Verify results**: Check `tar_read(us_text)` for completeness
4. **Proceed to Days 2-3**: Training data preparation (see `docs/plan_phase0.md`)

---

## References

- [AWS Lambda Container Images](https://docs.aws.amazon.com/lambda/latest/dg/images-create.html)
- [Amazon ECR User Guide](https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html)
- [Docling Documentation](https://github.com/DS4SD/docling)
- [paws R package](https://paws-r.github.io/)
- [Project Phase 0 Plan](plan_phase0.md)
