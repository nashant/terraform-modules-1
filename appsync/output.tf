output "logging_role" {
  description = "The IAM role that the AppSync GraphQL API uses for CloudWatch logging."
  value       = aws_iam_role.appsync_logging
}
output "logging_policy" {
  description = "The IAM policy that is attached to the `logging_role` IAM role."
  value       = aws_iam_role_policy.appsync_logging
}
output "graphql_api" {
  description = "The GraphQL API resource that was created."
  value       = aws_appsync_graphql_api.api
}
output "functions" {
  description = "A map of AppSync function resources that were created. The map keys correspond to the map keys in the `functions` input variable."
  value       = aws_appsync_function.functions
}
output "unit_resolvers" {
  description = "A map of AppSync unit resolver resources that were created. The map keys correspond to the map keys in the `unit_resolvers` input variable."
  value       = aws_appsync_resolver.pipelines
}
output "pipeline_resolvers" {
  description = "A map of AppSync pipeline resolver resources that were created. The map keys correspond to the map keys in the `pipeline_resolvers` input variable."
  value       = aws_appsync_resolver.pipelines
}
output "log_group" {
  description = "The CloudWatch log group resource that was automatically created by the AppSync API."
  value       = data.aws_cloudwatch_log_group.api
}
