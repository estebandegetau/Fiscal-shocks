# Lambda PDF Extraction - Quick Start Guide

## 5-Minute Setup

### 1. Prerequisites (2 min)

```bash
# Install R packages
R -e 'install.packages(c("paws.storage", "paws.compute", "dotenv", "furrr"))'

# Install Docker
# macOS/Windows: Download Docker Desktop
# Linux: sudo apt-get install docker.io

# Verify AWS CLI
aws --version
# If not installed: pip install awscli && aws configure
```

### 2. Configure (1 min)

```bash
# Copy environment template
cp .env.example .env

# Edit .env with your AWS credentials
# AWS_ACCESS_KEY_ID=AKIA...
# AWS_SECRET_ACCESS_KEY=xxx...
# AWS_DEFAULT_REGION=us-east-1
```

### 3. Deploy Lambda (10-15 min)

```bash
./lambda_deploy.sh
```

### 4. Test (2 min)

```r
source("R/pull_text_lambda.R")
dotenv::load_dot_env()

# Test single PDF
pull_text_lambda("https://www.govinfo.gov/content/pkg/ERP-2020/pdf/ERP-2020.pdf")
```

### 5. Update Pipeline (1 min)

```r
# In _targets.R, replace:
# pull_text_docling(us_urls_vector)

# With:
pull_text_lambda(us_urls_vector)
```

---

## Common Commands

### Deploy/Update Lambda
```bash
./lambda_deploy.sh
```

### Run Full Pipeline
```r
tar_make()
```

### View Lambda Logs
```bash
aws logs tail /aws/lambda/fiscal-shocks-pdf-extractor --follow
```

### List S3 Results
```bash
aws s3 ls s3://fiscal-shocks-pdfs/extracted/ --recursive
```

### Clean Up AWS Resources
```bash
# Delete function
aws lambda delete-function --function-name fiscal-shocks-pdf-extractor

# Delete S3 bucket
aws s3 rb s3://fiscal-shocks-pdfs --force
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Credentials not configured" | Create `.env` from `.env.example` |
| "Function not found" | Run `./lambda_deploy.sh` |
| "Timeout" | Increase `max_wait_time` in `pull_text_lambda()` |
| "Memory exceeded" | Update Lambda config: `--memory-size 5120` |

---

## Performance

- **Before**: 17+ hours (350 PDFs, laptop)
- **After**: 5-10 minutes (350 parallel Lambdas)
- **Cost**: ~$6 per full extraction

---

## Documentation

- Full guide: [`docs/lambda_deployment_guide.md`](lambda_deployment_guide.md)
- Targets integration: [`docs/lambda_targets_integration.md`](lambda_targets_integration.md)
- Implementation summary: [`docs/days_1-2_implementation_summary.md`](days_1-2_implementation_summary.md)
- Phase 0 plan: [`docs/plan_phase0.md`](plan_phase0.md)
