data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

// Create a role that allows the AppSync API to do logging
resource "aws_iam_role" "appsync_logging" {
  name_prefix        = "AppSyncLogging"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "appsync.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

// Create a policy for linking to the AppSync logging role
resource "aws_iam_role_policy" "appsync_logging" {
  name_prefix = "AppSyncLogging"
  role        = aws_iam_role.appsync_logging.id
  policy      = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": [
                "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
            ]
        }
    ]
}
EOF
}

// Create the GraphQL API
resource "aws_appsync_graphql_api" "api" {
  authentication_type = var.authentication_types[0]
  name                = var.name
  schema              = var.schema
  tags                = var.tags

  log_config {
    cloudwatch_logs_role_arn = aws_iam_role.appsync_logging.arn
    exclude_verbose_content  = var.logging_exclude_verbose_content
    field_log_level          = var.logging_level
  }

  // Only put the openid_connect_config block in the main block if OpenID is the first auth mechanism
  dynamic "openid_connect_config" {
    for_each = var.authentication_types[0] == "OPENID_CONNECT" ? [1] : []
    content {
      issuer    = lookup(var.openid_connect_config, "issuer", null)
      auth_ttl  = lookup(var.openid_connect_config, "auth_ttl", null)
      client_id = lookup(var.openid_connect_config, "client_id", null)
      iat_ttl   = lookup(var.openid_connect_config, "iat_ttl", null)
    }
  }

  // Only put the user_pool_config block in the main block if Cognito is the first auth mechanism
  dynamic "user_pool_config" {
    for_each = var.authentication_types[0] == "AMAZON_COGNITO_USER_POOLS" ? [1] : []
    content {
      default_action      = lookup(var.user_pool_config, "default_action", null)
      user_pool_id        = lookup(var.user_pool_config, "user_pool_id", null)
      app_id_client_regex = lookup(var.user_pool_config, "app_id_client_regex", null)
      aws_region          = lookup(var.user_pool_config, "aws_region", null)
    }
  }

  // Add all additional auth mechanisms
  dynamic "additional_authentication_provider" {
    // Loop for all except the first one
    for_each = length(var.authentication_types) > 1 ? slice(var.authentication_types, 1, length(var.authentication_types) - 1) : []
    content {
      authentication_type = additional_authentication_provider.value
      // Only add the 'openid_connect_config' block if this is an OpenID mechanism
      dynamic "openid_connect_config" {
        for_each = additional_authentication_provider.value == "OPENID_CONNECT" ? [1] : []
        content {
          issuer    = lookup(var.openid_connect_config, "issuer", null)
          auth_ttl  = lookup(var.openid_connect_config, "auth_ttl", null)
          client_id = lookup(var.openid_connect_config, "client_id", null)
          iat_ttl   = lookup(var.openid_connect_config, "iat_ttl", null)
        }
      }
      dynamic "user_pool_config" {
        // Only add the 'user_pool_config' block if this is a Cognito mechanism
        for_each = additional_authentication_provider.value == "AMAZON_COGNITO_USER_POOLS" ? [1] : []
        content {
          user_pool_id        = lookup(var.user_pool_config, "user_pool_id", null)
          app_id_client_regex = lookup(var.user_pool_config, "app_id_client_regex", null)
          aws_region          = lookup(var.user_pool_config, "aws_region", null)
        }
      }
    }
  }
}

// Get the log group that was automatically created by the GraphQL API
data "aws_cloudwatch_log_group" "api" {
  name = "/aws/appsync/apis/${aws_appsync_graphql_api.api.id}"
}

// Create the functions that can be used in pipelines
resource "aws_appsync_function" "functions" {
  for_each                  = var.functions
  depends_on                = [var.datasources]
  api_id                    = aws_appsync_graphql_api.api.id
  data_source               = each.value.datasource_name
  name                      = each.value.name
  request_mapping_template  = each.value.request_mapping_template == "" ? " " : each.value.request_mapping_template
  response_mapping_template = each.value.response_mapping_template == "" ? " " : each.value.response_mapping_template
}

// Create the unit resolvers
resource "aws_appsync_resolver" "unit" {
  for_each          = var.unit_resolvers
  depends_on        = [var.datasources]
  api_id            = aws_appsync_graphql_api.api.id
  type              = each.value.type
  field             = each.value.name
  data_source       = each.value.datasource_name
  request_template  = each.value.request_mapping_template == "" ? " " : each.value.request_mapping_template
  response_template = each.value.response_mapping_template == "" ? " " : each.value.response_mapping_template
  kind              = "UNIT"
}

// Create the pipeline resolvers
resource "aws_appsync_resolver" "pipelines" {
  for_each          = var.pipeline_resolvers
  api_id            = aws_appsync_graphql_api.api.id
  type              = each.value.type
  field             = each.value.name
  request_template  = each.value.request_mapping_template == "" ? " " : each.value.request_mapping_template
  response_template = each.value.response_mapping_template == "" ? " " : each.value.response_mapping_template
  kind              = "PIPELINE"
  pipeline_config {
    functions = [
      for function in each.value.functions :
      aws_appsync_function.functions[function].function_id
    ]
  }
}
