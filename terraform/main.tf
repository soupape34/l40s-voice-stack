terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

data "aws_instance" "voice" {
  instance_id = var.instance_id
}

resource "aws_iam_role" "voice_ec2" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "voice_self_stop" {
  name = "${var.project_name}-self-stop"
  role = aws_iam_role.voice_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StopOwnInstance"
        Effect = "Allow"
        Action = ["ec2:StopInstances"]
        Resource = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/${var.instance_id}"
      },
      {
        Sid    = "DescribeForStop"
        Effect = "Allow"
        Action = ["ec2:DescribeInstances"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "voice_ec2" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.voice_ec2.name
  tags = var.tags
}

# Associe le profile à l'instance existante (API AWS, pas de resource TF dédiée)
resource "null_resource" "associate_instance_profile" {
  triggers = {
    instance_id = var.instance_id
    profile     = aws_iam_instance_profile.voice_ec2.name
  }

  provisioner "local-exec" {
    command = <<-EOT
      ASSOC=$(aws ec2 describe-iam-instance-profile-associations \
        --filters Name=instance-id,Values=${var.instance_id} \
        --query 'IamInstanceProfileAssociations[0].AssociationId' --output text \
        --region ${var.aws_region} 2>/dev/null || echo "None")
      if [ "$ASSOC" != "None" ] && [ -n "$ASSOC" ]; then
        aws ec2 disassociate-iam-instance-profile \
          --association-id "$ASSOC" --region ${var.aws_region} || true
      fi
      aws ec2 associate-iam-instance-profile \
        --instance-id ${var.instance_id} \
        --iam-instance-profile Name=${aws_iam_instance_profile.voice_ec2.name} \
        --region ${var.aws_region}
    EOT
  }

  depends_on = [aws_iam_instance_profile.voice_ec2]
}
