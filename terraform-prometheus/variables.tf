variable "vpc_id" {}
variable "subnet_id" {} # Choose a subnet in the same VPC as your EKS cluster
variable "key_name" {}
variable "allow_ingress_cidrs_to_prom" {
  default = ["0.0.0.0/0"] # Change to restrict access
}