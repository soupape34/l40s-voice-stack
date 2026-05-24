output "instance_id" {
  value = var.instance_id
}

output "instance_profile_arn" {
  value = aws_iam_instance_profile.voice_ec2.arn
}

output "iam_role_arn" {
  value = aws_iam_role.voice_ec2.arn
}
