# REST API (v1), not HTTP API (v2) — Usage Plans/API Keys for per-client throttling are a REST
# API feature only.
resource "aws_api_gateway_rest_api" "this" {
  name = "net-lab-api"
}

resource "aws_api_gateway_resource" "hello" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "hello"
}

# ── Custom authorizer — a bad/missing token proves the 403 ─────────────────────────────────
resource "aws_api_gateway_authorizer" "custom" {
  name            = "net-lab-authorizer"
  rest_api_id     = aws_api_gateway_rest_api.this.id
  authorizer_uri  = aws_lambda_function.authorizer.invoke_arn
  type            = "TOKEN"
  identity_source = "method.request.header.Authorization"
}

resource "aws_lambda_permission" "apigw_invoke_authorizer" {
  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/authorizers/${aws_api_gateway_authorizer.custom.id}"
}

# ── GET /hello — behind the authorizer AND requires an API key (throttling below) ──────────
resource "aws_api_gateway_method" "hello_get" {
  rest_api_id      = aws_api_gateway_rest_api.this.id
  resource_id      = aws_api_gateway_resource.hello.id
  http_method      = "GET"
  authorization    = "CUSTOM"
  authorizer_id    = aws_api_gateway_authorizer.custom.id
  api_key_required = true
}

resource "aws_api_gateway_integration" "hello_get" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.hello.id
  http_method             = aws_api_gateway_method.hello_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.hello.invoke_arn
}

resource "aws_lambda_permission" "apigw_invoke_hello" {
  statement_id  = "AllowAPIGatewayInvokeHello"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.hello.id,
      aws_api_gateway_method.hello_get.id,
      aws_api_gateway_integration.hello_get.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_api_gateway_integration.hello_get]
}

resource "aws_api_gateway_stage" "lab" {
  deployment_id = aws_api_gateway_deployment.this.id
  rest_api_id   = aws_api_gateway_rest_api.this.id
  stage_name    = "lab"
}

# ── Per-client usage plan — proves rate limiting is a separate control from auth ────────────
resource "aws_api_gateway_api_key" "client1" {
  name = "net-lab-client1"
}

resource "aws_api_gateway_usage_plan" "this" {
  name = "net-lab-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_stage.lab.stage_name
  }

  throttle_settings {
    rate_limit  = 5
    burst_limit = 10
  }
}

resource "aws_api_gateway_usage_plan_key" "client1" {
  key_id        = aws_api_gateway_api_key.client1.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.this.id
}
