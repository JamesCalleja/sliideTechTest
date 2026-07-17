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

# IAM Role for API Gateway to write to Kinesis
resource "aws_iam_role" "apigw_kinesis" {
  name = "sliide-apigw-kinesis-role-${var.environment}"

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
  name        = "sliide-apigw-kinesis-policy-${var.environment}"
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
{
  "StreamName": "${var.kinesis_stream_name}",
  "Data": "$util.base64Encode($input.json('$'))",
  "PartitionKey": "$util.defaultIfNull($input.path('$.userId'), $context.requestId)"
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
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.kinesis
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
