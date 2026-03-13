# -----------------------------------------------------------------------------
# CE AMI
#
# Two paths:
#   1. Direct: set ami_id to use an existing AMI.
#   2. Import: set ce_image_download_url + s3_bucket_name. Terraform will
#      download the image, upload to S3, and run ec2 import-image.
#      Subsequent applies skip the import if the AMI already exists.
#
# The download URL comes from the F5 XC Console: create an SMSv2 site,
# then click ... > Copy Image Name.
# -----------------------------------------------------------------------------

locals {
  image_name = "${var.site_name}-ce-image"

  # Strip compression extensions to get the base image filename for S3
  _basename = var.ce_image_download_url != null ? basename(var.ce_image_download_url) : null
  _stripped = local._basename != null ? replace(replace(local._basename, ".gz", ""), ".tar", "") : null
  s3_key    = local._stripped

  # Detect disk format from filename (vhd, vmdk, raw, ova)
  disk_format = (
    local._stripped != null
    ? (can(regex("\\.vhd$", local._stripped)) ? "VHD" :
      can(regex("\\.vmdk$", local._stripped)) ? "VMDK" :
    can(regex("\\.ova$", local._stripped)) ? "OVA" : "RAW")
    : "RAW"
  )

  ce_ami_id = coalesce(
    var.ami_id,
    try(data.aws_ami.imported[0].id, null),
  )
}

# ---------------------------------------------------------------------------
# S3 bucket for staging CE image import (conditional)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "ce_image_staging" {
  count         = var.ce_image_download_url != null && var.ami_id == null ? 1 : 0
  bucket        = var.s3_bucket_name
  force_destroy = true
  tags          = merge(local.common_tags, { Name = var.s3_bucket_name })
}

# ---------------------------------------------------------------------------
# Import CE image from download URL (conditional)
# ---------------------------------------------------------------------------

resource "terraform_data" "ami_import" {
  count      = var.ce_image_download_url != null && var.ami_id == null ? 1 : 0
  depends_on = [aws_s3_bucket.ce_image_staging]

  triggers_replace = [var.ce_image_download_url]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      AWS_PROFILE = var.aws_profile != null ? var.aws_profile : ""
      AWS_REGION  = var.aws_region
    }
    command = <<-SCRIPT
      set -euo pipefail
      [[ -z "$AWS_PROFILE" ]] && unset AWS_PROFILE

      REGION="$AWS_REGION"
      BUCKET="${var.s3_bucket_name}"
      IMAGE_NAME="${local.image_name}"
      S3_KEY="${local.s3_key}"

      # --- Check if AMI already exists with this name ---
      EXISTING=$(aws ec2 describe-images --region "$REGION" \
        --owners self \
        --filters "Name=tag:Name,Values=$IMAGE_NAME" \
        --query 'Images[0].ImageId' --output text 2>/dev/null || echo "None")

      if [[ "$EXISTING" != "None" && "$EXISTING" != "" ]]; then
        echo "AMI '$IMAGE_NAME' already exists: $EXISTING. Skipping import."
        exit 0
      fi

      # --- Ensure vmimport service role exists ---
      if ! aws iam get-role --role-name vmimport --region "$REGION" >/dev/null 2>&1; then
        echo "Creating vmimport service role..."
        aws iam create-role --role-name vmimport --region "$REGION" \
          --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
              "Effect": "Allow",
              "Principal": { "Service": "vmie.amazonaws.com" },
              "Action": "sts:AssumeRole",
              "Condition": {
                "StringEquals": { "sts:ExternalId": "vmimport" }
              }
            }]
          }'

        aws iam put-role-policy --role-name vmimport --region "$REGION" \
          --policy-name vmimport-policy \
          --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
              {
                "Effect": "Allow",
                "Action": ["s3:GetBucketLocation", "s3:GetObject", "s3:ListBucket"],
                "Resource": ["arn:aws-us-gov:s3:::'"$BUCKET"'", "arn:aws-us-gov:s3:::'"$BUCKET"'/*"]
              },
              {
                "Effect": "Allow",
                "Action": [
                  "ec2:ModifySnapshotAttribute", "ec2:CopySnapshot",
                  "ec2:RegisterImage", "ec2:Describe*"
                ],
                "Resource": "*"
              }
            ]
          }'

        echo "Waiting for IAM role propagation..."
        sleep 15
      fi

      # Use pre-downloaded image if available, otherwise download
      CE_IMAGE_FILE="${var.ce_image_file != null ? var.ce_image_file : ""}"
      if [[ -n "$CE_IMAGE_FILE" && -f "$CE_IMAGE_FILE" ]]; then
        echo "Using pre-downloaded CE image: $CE_IMAGE_FILE ($(du -h "$CE_IMAGE_FILE" | cut -f1))"
        RAW_FILE="$CE_IMAGE_FILE"
      else
        WORK_DIR=$(mktemp -d)
        trap 'rm -rf "$WORK_DIR"' EXIT

        echo "Downloading CE image..."
        curl -fL --progress-bar \
          -o "$WORK_DIR/$(basename "${var.ce_image_download_url}")" \
          "${var.ce_image_download_url}"

        # Decompress / extract
        if ls "$WORK_DIR"/*.gz 1>/dev/null 2>&1; then
          echo "Decompressing .gz ..."
          gunzip "$WORK_DIR/"*.gz
        fi
        if ls "$WORK_DIR"/*.tar 1>/dev/null 2>&1; then
          echo "Extracting .tar ..."
          cd "$WORK_DIR" && tar xf *.tar && rm -f *.tar && cd -
        fi

        RAW_FILE=$(find "$WORK_DIR" -type f \( -name "*.vhd" -o -name "*.vmdk" -o -name "*.raw" -o -name "*.img" -o -name "*.ova" \) | head -1)
        if [[ -z "$RAW_FILE" ]]; then
          RAW_FILE=$(find "$WORK_DIR" -type f -printf '%s %p\n' | sort -rn | head -1 | awk '{print $2}')
        fi
        echo "Image file: $RAW_FILE ($(du -h "$RAW_FILE" | cut -f1))"
      fi

      echo "Uploading to s3://$BUCKET/$S3_KEY ..."
      aws s3 cp "$RAW_FILE" "s3://$BUCKET/$S3_KEY" --region "$REGION"

      echo "Starting AMI import..."
      IMPORT_TASK_ID=$(aws ec2 import-image --region "$REGION" \
        --description "$IMAGE_NAME" \
        --license-type BYOL \
        --disk-containers "Description=$IMAGE_NAME,Format=${local.disk_format},UserBucket={S3Bucket=$BUCKET,S3Key=$S3_KEY}" \
        --query 'ImportTaskId' --output text)

      echo "Import task: $IMPORT_TASK_ID — waiting for completion..."

      while true; do
        STATUS=$(aws ec2 describe-import-image-tasks --region "$REGION" \
          --import-task-ids "$IMPORT_TASK_ID" \
          --query 'ImportImageTasks[0].Status' --output text)
        PROGRESS=$(aws ec2 describe-import-image-tasks --region "$REGION" \
          --import-task-ids "$IMPORT_TASK_ID" \
          --query 'ImportImageTasks[0].Progress' --output text 2>/dev/null || echo "?")
        echo "  Status: $STATUS  Progress: $PROGRESS%"

        if [[ "$STATUS" == "completed" ]]; then
          AMI_ID=$(aws ec2 describe-import-image-tasks --region "$REGION" \
            --import-task-ids "$IMPORT_TASK_ID" \
            --query 'ImportImageTasks[0].ImageId' --output text)
          echo "Import complete: $AMI_ID"

          # Tag the AMI so data.aws_ami can find it
          aws ec2 create-tags --region "$REGION" \
            --resources "$AMI_ID" \
            --tags Key=Name,Value="$IMAGE_NAME"

          echo "AMI tagged: $IMAGE_NAME"
          break
        elif [[ "$STATUS" == "deleted" || "$STATUS" == "failed" ]]; then
          MSG=$(aws ec2 describe-import-image-tasks --region "$REGION" \
            --import-task-ids "$IMPORT_TASK_ID" \
            --query 'ImportImageTasks[0].StatusMessage' --output text 2>/dev/null || echo "unknown")
          echo "ERROR: Import failed — $MSG"
          exit 1
        fi
        sleep 30
      done

      # Clean up S3 staging object
      echo "Cleaning up S3 staging object..."
      aws s3 rm "s3://$BUCKET/$S3_KEY" --region "$REGION" || true
    SCRIPT
  }
}

# ---------------------------------------------------------------------------
# Look up the imported AMI by its Name tag
# ---------------------------------------------------------------------------

data "aws_ami" "imported" {
  count      = var.ce_image_download_url != null && var.ami_id == null ? 1 : 0
  depends_on = [terraform_data.ami_import]

  most_recent = true
  owners      = ["self"]

  filter {
    name   = "tag:Name"
    values = [local.image_name]
  }
}
