variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "instance_id" {
  type        = string
  description = "Existing EC2 instance ID (g6e.xlarge voice stack)"
  default     = "i-0e278c6ee4963512e"
}

variable "project_name" {
  type    = string
  default = "voice-stack"
}

variable "tags" {
  type = map(string)
  default = {
    Project = "voice-stack"
    Managed = "terraform"
  }
}
