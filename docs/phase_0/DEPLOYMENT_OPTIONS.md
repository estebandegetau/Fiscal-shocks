# Lambda Deployment Options

## Issue: Docker Not Available in Dev Container

The deployment script (`lambda_deploy.sh`) requires Docker to build Python packages compatible with AWS Lambda's Linux environment. However, **Docker daemon is not available inside the dev container**.

### Solution Options

You have **three options** to deploy the Lambda function:

---

## Option 1: Deploy from Your Local Machine (Recommended)

Run the deployment script directly from your local machine (outside the dev container).

### Steps:

1. **Exit the dev container** or open a new terminal on your local machine

2. **Navigate to project directory**:
   ```bash
   cd /path/to/Fiscal-shocks
   ```

3. **Ensure Docker Desktop is running**:
   - macOS/Windows: Start Docker Desktop application
   - Linux: `sudo systemctl start docker`

4. **Copy `.env` file** (if you created it in the container):
   ```bash
   # If .env is in container, copy it out first
   # Or create .env locally from .env.example
   cp .env.example .env
   # Edit with your AWS credentials
   ```

5. **Run deployment**:
   ```bash
   ./lambda_deploy.sh
   ```

6. **Expected runtime**: 10-15 minutes (building Docker image for Lambda layer)

---

## Option 2: Use Pre-built Lambda Layer (Fast, No Docker Required)

Skip the Docker build step by using a pre-built Lambda layer or simplified deployment.

### Steps:

I can create a simplified version that:
- Uses `pip install --target` instead of Docker
- Packages dependencies locally
- May not be 100% compatible with Lambda but works for most cases

**Would you like me to create this simplified deployment script?**

---

## Option 3: Deploy from Cloud IDE / EC2 (If available)

If you have access to a cloud environment with Docker:

1. Clone the repository to AWS Cloud9, EC2, or another cloud IDE
2. Run `./lambda_deploy.sh` there
3. Everything deploys directly to your AWS account

---

## Recommended Approach

**For now, use Option 1** (deploy from local machine):

1. ✅ S3 bucket already created: `fiscal-shocks-pdfs`
2. ⏳ Need to build Lambda layer with Docker (run locally)
3. ⏳ Deploy Lambda function

### Quick Test (Without Full Deployment)

You can test the R code without deploying Lambda:

```r
# In R console
source("R/pull_text_lambda.R")
dotenv::load_dot_env()

# This will fail (Lambda not deployed yet) but shows you the code structure
# pull_text_lambda("https://example.com/test.pdf")
```

---

## Next Steps

**Choose one of the following:**

### A. Deploy from Local Machine (Recommended)
1. Exit dev container or open local terminal
2. Ensure Docker Desktop is running
3. Run: `./lambda_deploy.sh`
4. Wait 10-15 minutes
5. Return to dev container and test with R

### B. Skip Lambda, Use Local Docling (Slower but works now)
1. Keep using `pull_text_docling()` in `_targets.R`
2. Accept 17+ hour runtime for 350 PDFs
3. Consider running overnight

### C. Wait for Simplified Deployment Script
1. I can create a Docker-free version
2. May have compatibility issues
3. Not guaranteed to work

---

## What's Already Done

✅ **AWS credentials configured** (tested successfully)
✅ **S3 bucket created**: `s3://fiscal-shocks-pdfs`
✅ **Python code ready**: `python/lambda_handler.py`
✅ **R wrapper ready**: `R/pull_text_lambda.R`
⏳ **Lambda layer**: Needs Docker to build
⏳ **Lambda function**: Needs layer to deploy

---

## Troubleshooting

### "Docker daemon not running"
- **In dev container**: This is expected, see options above
- **On local machine**: Start Docker Desktop

### "Cannot connect to Docker socket"
- Dev containers don't have Docker daemon access
- Use Option 1 (deploy from local machine)

### "AWS credentials not working"
- The `.env` file loading is now fixed in `lambda_deploy.sh`
- Your credentials are confirmed working (S3 bucket created)

---

## Cost Note

The deployment itself is **free** - you only pay when the Lambda function runs. So there's no rush to deploy if you want to think about which option to use.

Current costs:
- S3 bucket (empty): $0.00
- Lambda function (not deployed): $0.00
- **Total so far**: $0.00

You'll only incur costs (~$6) when you actually run the PDF extraction.
