variable "aws_region" {
  description = "The AWS region to deploy to (e.g. us-west-2)"
  type        = string
  default     = "us-west-2"
}

variable "project" {
  description = "The project name"
  type        = string
  default     = "monarch"
}

variable "tenant" {
  description = "The tenant"
  type        = string
  default     = "alphadc1"
}

variable "environment" {
  description = "The environment"
  type        = string
  default     = "alpha"
}

variable "vpc_name" {
  description = "The VPC name"
  type        = string
  default     = "default"
}

variable "desired_count" {
  description = "The desired count of API service"
  type        = number
  default     = 1
}

variable "enable_acm" {
  description = "Enable AWS certificate manager support"
  type        = bool
  default     = true
}

variable "api_fqdn" {
  description = "The API FQDN"
  type        = string
  default     = "*.example.com"
}

variable "db_size" {
  description = "The database instance type"
  type        = string
  default     = "db.t3.micro"
}

variable "monitor_interval" {
  description = "The RDS monitor interval"
  type        = number
  default     = 0
}

variable "performance_insight" {
  description = "Enable RDS performance insight"
  type        = bool
  default     = true
}

variable "db_username" {
  description = "The database master user name"
  type        = string
  default     = "monarch"
}

variable "db_password" {
  description = "The database master user password"
  type        = string
  default     = "password"
}

variable "kong_password" {
  description = "The kong database password"
  type        = string
  default     = "password"
}
