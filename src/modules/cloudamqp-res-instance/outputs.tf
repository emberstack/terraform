output "id" {
  description = "The instance identifier."
  value       = cloudamqp_instance.this.id
}

output "name" {
  description = "Name of the instance."
  value       = cloudamqp_instance.this.name
}

output "host" {
  description = "External hostname of the instance."
  value       = cloudamqp_instance.this.host
}

output "host_internal" {
  description = "Internal hostname of the instance, reachable from inside its VPC and across its private link."
  value       = cloudamqp_instance.this.host_internal
}

output "vhost" {
  description = "The instance's virtual host."
  value       = cloudamqp_instance.this.vhost
}

output "url" {
  description = "Connection URL of the instance. Carries the broker credentials."
  value       = cloudamqp_instance.this.url
  sensitive   = true
}

output "apikey" {
  description = "API key of the instance, for the per-instance CloudAMQP API."
  value       = cloudamqp_instance.this.apikey
  sensitive   = true
}

output "dedicated" {
  description = "Whether the instance runs on dedicated servers."
  value       = cloudamqp_instance.this.dedicated
}

output "backend" {
  description = "Broker software the plan runs, for example `rabbitmq` or `lavinmq`."
  value       = cloudamqp_instance.this.backend
}

output "rmq_version" {
  description = "RabbitMQ version the instance runs."
  value       = cloudamqp_instance.this.rmq_version
}

output "private_link" {
  description = <<-EOT
    The private link's service end, or null when `private_link` is not set.

    `service_name` is what the consumer connects to — on Azure, the alias a private
    endpoint targets. `status` is `enabled`, `pending` or `disabled`.
  EOT
  value = var.private_link == null ? null : {
    service_name = cloudamqp_vpc_connect.this[0].service_name
    status       = cloudamqp_vpc_connect.this[0].status
  }
}
