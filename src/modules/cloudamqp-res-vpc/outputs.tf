output "id" {
  description = "The VPC identifier. Pass it to an instance's `vpc_id` to place the instance in this VPC."
  value       = cloudamqp_vpc.this.id
}

output "name" {
  description = "Name of the VPC."
  value       = cloudamqp_vpc.this.name
}

output "vpc_name" {
  description = "The name the VPC carries at the hosting cloud provider."
  value       = cloudamqp_vpc.this.vpc_name
}

output "region" {
  description = "Region the VPC is hosted in."
  value       = cloudamqp_vpc.this.region
}

output "subnet" {
  description = "The VPC's subnet in CIDR notation."
  value       = cloudamqp_vpc.this.subnet
}
