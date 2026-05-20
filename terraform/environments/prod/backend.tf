# Run scripts/bootstrap-state.sh first, then replace ACCOUNT_ID with your AWS account ID:
#   aws sts get-caller-identity --query Account --output text
terraform {
  backend "s3" {
    bucket         = "petclinic-terraform-state-569144120198"
    key            = "petclinic/prod/terraform.tfstate"
    region         = "eu-central-1"
    encrypt        = true
    dynamodb_table = "petclinic-terraform-locks"
  }
}
