variable "dockerfile_dir" {
  type = string
  description = "The directory that contains the Dockerfile"
  default = "."
}

variable "ecr_repository_url" {
  type        = string
  description = "Full url for the ECR repository"
  default = "https://070009232298.dkr.ecr.eu-west-1.amazonaws.com/app-repo"
}

variable "docker_image_tag" {
  type        = string
  description = "This is the tag which will be used for the image that you created"
  default     = "latest"
}
