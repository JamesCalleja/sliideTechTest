resource "aws_api_gateway_rest_api" "events" {
  name        = "sliide-events-api-${var.environment}"
  description = "Sliide mobile apps event ingestion gateway"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Environment = var.environment
  }
}

resource "aws_api_gateway_resource" "events" {
  rest_api_id = aws_api_gateway_rest_api.events.id
  parent_id   = aws_api_gateway_rest_api.events.root_resource_id
  path_part   = "events"
}

resource "aws_api_gateway_method" "post" {
  rest_api_id   = aws_api_gateway_rest_api.events.id
  resource_id   = aws_api_gateway_resource.events.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method_response" "post_200" {
  rest_api_id = aws_api_gateway_rest_api.events.id
  resource_id = aws_api_gateway_resource.events.id
  http_method = aws_api_gateway_method.post.http_method
  status_code = "200"
}

resource "random_id" "apigw_suffix" {
  byte_length = 4
}

# IAM Role for API Gateway to write to Kinesis
resource "aws_iam_role" "apigw_kinesis" {
  name = "sliide-apigw-kinesis-role-${var.environment}-${random_id.apigw_suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "apigw_kinesis_policy" {
  name        = "sliide-apigw-kinesis-policy-${var.environment}-${random_id.apigw_suffix.hex}"
  description = "Allows API Gateway to write events to Kinesis stream"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:PutRecord",
          "kinesis:PutRecords"
        ]
        Resource = [
          var.kinesis_stream_arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource = [
          var.kms_key_arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "apigw_kinesis" {
  role       = aws_iam_role.apigw_kinesis.name
  policy_arn = aws_iam_policy.apigw_kinesis_policy.arn
}

resource "aws_api_gateway_integration" "kinesis" {
  rest_api_id             = aws_api_gateway_rest_api.events.id
  resource_id             = aws_api_gateway_resource.events.id
  http_method             = aws_api_gateway_method.post.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  credentials             = aws_iam_role.apigw_kinesis.arn
  uri                     = "arn:aws:apigateway:${var.region}:kinesis:action/PutRecord"

  # Direct service integration request mapping template
  # The PartitionKey is mapped to $.userId or a default random uuid if userId is not present
  request_templates = {
    "application/json" = <<EOF
#set($userId = $input.path('$.userId'))
#if("$!userId" == "")
  #set($userId = $context.requestId)
#end
{
  "StreamName": "${var.kinesis_stream_name}",
  "Data": "$util.base64Encode($input.json('$'))",
  "PartitionKey": "$userId"
}
EOF
  }
}

resource "aws_api_gateway_integration_response" "kinesis_200" {
  rest_api_id = aws_api_gateway_rest_api.events.id
  resource_id = aws_api_gateway_resource.events.id
  http_method = aws_api_gateway_method.post.http_method
  status_code = aws_api_gateway_method_response.post_200.status_code

  # Respond with event ID and status
  response_templates = {
    "application/json" = <<EOF
{
  "status": "success",
  "requestId": "$context.requestId"
}
EOF
  }

  depends_on = [
    aws_api_gateway_integration.kinesis
  ]
}

resource "aws_api_gateway_deployment" "events" {
  rest_api_id = aws_api_gateway_rest_api.events.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.events.id,
      aws_api_gateway_method.post.id,
      aws_api_gateway_integration.kinesis.id,
      aws_api_gateway_integration.kinesis.request_templates,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.kinesis,
    aws_api_gateway_integration_response.kinesis_200,
    aws_api_gateway_method_response.post_200
  ]
}

resource "aws_api_gateway_stage" "events" {
  deployment_id = aws_api_gateway_deployment.events.id
  rest_api_id   = aws_api_gateway_rest_api.events.id
  stage_name    = var.environment

  tags = {
    Environment = var.environment
  }
}

# Regional Web Application Firewall (WAF) to protect the API Gateway endpoint
resource "aws_wafv2_web_acl" "api_waf" {
  name        = "sliide-api-waf-${var.environment}"
  description = "WAF for Sliide events API Gateway"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # 1. Rate-limiting Rule (DDoS & API abuse mitigation)
  rule {
    name     = "RateLimit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000 # Max 2000 requests per 5 minutes per IP
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "SliideApiRateLimit"
      sampled_requests_enabled   = true
    }
  }

  # 2. AWS Managed Common Rule Set (protection against SQLi, XSS, etc.)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "SliideApiWAF"
    sampled_requests_enabled   = true
  }

  tags = {
    Environment = var.environment
  }
}

# Associate the WAF with the API Gateway stage
resource "aws_wafv2_web_acl_association" "api_waf_assoc" {
  resource_arn = aws_api_gateway_stage.events.arn
  web_acl_arn  = aws_wafv2_web_acl.api_waf.arn
}
