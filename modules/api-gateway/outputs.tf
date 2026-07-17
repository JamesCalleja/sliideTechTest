output "api_url" {
  value       = "${aws_api_gateway_stage.events.invoke_url}/events"
  description = "Events Ingestion HTTPS URL"
}
