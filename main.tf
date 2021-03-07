terraform {
  required_providers {
    aws = {
      version = "~>3.26.0"
    }
  }
}

data "aws_vpc" "monarch" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

data "aws_subnet_ids" "private" {
  vpc_id = data.aws_vpc.monarch.id
  filter {
    name   = "tag:Type"
    values = ["private"]
  }
  filter {
    name   = "tag:Service"
    values = ["true"]
  }
}

data "aws_subnet_ids" "public" {
  vpc_id = data.aws_vpc.monarch.id
  filter {
    name   = "tag:Type"
    values = ["public"]
  }
  filter {
    name   = "tag:Service"
    values = ["true"]
  }
}

resource "aws_s3_bucket" "logs" {
  bucket = "${var.project}-${var.environment}-log"
  acl    = "private"
  tags = {
    Name        = "${var.project}-${var.environment}-log"
    Environment = var.environment
    Service     = var.project
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

}

# ECS cluster

resource "aws_ecs_cluster" "monarch" {
  name               = "${var.project}-${var.environment}-api"
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
}

resource "aws_security_group" "alb" {
  name        = "${var.project}-${var.environment}-alb"
  description = "api alb security security group"
  vpc_id      = data.aws_vpc.monarch.id
  ingress {
    description = "allow HTTPS access"
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "${var.project}-${var.environment}-alb"
    Type        = "api"
    Environment = var.environment
    Tenant      = var.environment
  }
}

resource "aws_lb" "api" {
  name                       = "${var.project}-${var.environment}-api"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = data.aws_subnet_ids.public.ids
  enable_deletion_protection = true
  tags = {
    Name        = "${var.project}-${var.environment}-api"
    Environment = var.environment
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.api.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-FS-1-2-2019-08"
  certificate_arn   = "arn:aws:acm:us-west-2:890186914595:certificate/299357f1-93bb-4450-9326-500dd00a1413"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

# ECS role for invocation
resource "aws_iam_role" "task_execute_role" {
  name               = "${var.project}-${var.environment}-EcsTaskExecute"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      }
    }
  ]
}
EOF
  tags = {
    Name        = "${var.project}-${var.environment}-EcsTaskExecute"
    Environment = var.environment
    Tenant      = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "task-execution-policy-attach" {
  role       = aws_iam_role.task_execute_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${var.project}-${var.environment}-api"
  retention_in_days = 30
}

resource "aws_security_group" "api" {
  name        = "${var.project}-${var.environment}-api"
  description = "OCR API security group"
  vpc_id      = data.aws_vpc.monarch.id
  ingress {
    description     = "Allow ALB HTTP access"
    protocol        = "tcp"
    from_port       = 8000
    to_port         = 8000
    security_groups = [aws_security_group.alb.id]
  }
  ingress {
    description     = "Allow internal access admin"
    protocol        = "tcp"
    from_port       = 8001
    to_port         = 8001
    cidr_blocks     = ["10.0.0.0/8"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "${var.project}-${var.environment}-api"
    Type        = "api"
    Environment = var.environment
  }
}

resource "aws_iam_role" "task_api_role" {
  name               = "${var.project}-${var.environment}-api"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      }
    }
  ]
}
EOF
  tags = {
    Name        = "${var.project}-${var.environment}-api"
    Environment = var.environment
  }
}
#"command": ["kong", "migrations", "up", "&&", "kong", "migrations", "finish"],

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.project}-${var.environment}-api"
  task_role_arn            = aws_iam_role.task_api_role.arn
  execution_role_arn       = aws_iam_role.task_execute_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048
  tags                     = {}
  container_definitions    = <<TASK_DEFINITION
  [
    {
      "name": "api",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 8000
        }
      ],
      "startTimeout": 30,
      "stopTimeout": 10,
      "image": "kong",
      "cpu": 1024,
      "memory": 2048,
      "memoryReservation": 128,
      "environment": [
        {
          "name": "KONG_DATABASE",
          "value": "postgres"
        },
        {
          "name": "KONG_PG_HOST",
          "value": "${aws_db_instance.api-db.address}"
        },
        {
          "name": "KONG_PG_USER",
          "value": "kong"
        },
        {
          "name": "KONG_PG_PASSWORD",
          "value": "${var.kong_password}"
        },
        {
          "name": "KONG_PROXY_ACCESS_LOG",
          "value": "/dev/stdout"
        },
        {
          "name": "KONG_ADMIN_ACCESS_LOG",
          "value": "/dev/stdout"
        },
        {
          "name": "KONG_PROXY_ERROR_LOG",
          "value": "/dev/stderr"
        },
        {
          "name": "KONG_ADMIN_ERROR_LOG",
          "value": "/dev/stderr"
        },
        {
          "name": "KONG_ADMIN_LISTEN",
          "value": "0.0.0.0:8001"
        }
      ],
      "mountPoints": [],
      "volumesFrom": [],
      "ulimits": [
        {
          "softLimit": 4096,
          "hardLimit": 8192,
          "name": "nofile"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "${aws_cloudwatch_log_group.api.name}",
          "awslogs-region": "${var.aws_region}",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
  TASK_DEFINITION
}

resource "aws_lb_target_group" "api" {
  name        = "${var.project}-${var.environment}-api"
  port        = 8000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.monarch.id
  health_check {
    path = "/"
    matcher = "200,202,401,404"
  }
  depends_on = [aws_lb.api]
}

resource "aws_ecs_service" "api" {
  name            = "${var.project}-${var.environment}-api"
  cluster         = aws_ecs_cluster.monarch.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  depends_on      = [aws_ecs_task_definition.api]
  network_configuration {
    assign_public_ip = false
    subnets          = data.aws_subnet_ids.private.ids
    security_groups  = [aws_security_group.api.id]
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = 8000
  }
  service_registries {
    container_name = "kong"
    registry_arn   = aws_service_discovery_service.kong.arn
  }
}

# Database

resource "aws_db_subnet_group" "monarch" {
  name       = "${var.project}-${var.environment}-db"
  subnet_ids = data.aws_subnet_ids.private.ids

  tags = {
    Name = "${var.project}-${var.environment}-db"
  }
}

resource "aws_security_group" "db" {
  name        = "${var.project}-${var.environment}-db"
  description = "API Database Security Group"
  vpc_id      = data.aws_vpc.monarch.id

  ingress {
    description = "Allow API access"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [
        aws_security_group.api.id
      ]
  }

  ingress {
    description = "Allow replica"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    self        = true
  }

  tags = {
    Name        = "${var.project}-${var.environment}-db"
    Environment = var.environment
    Tenant      = var.tenant
    Service     = var.project
  }
}

resource "aws_iam_role" "rds-monitor" {
  name = "${var.project}-${var.environment}-rds-monitor"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Effect": "Allow",
      "Principal": {
        "Service": "monitoring.rds.amazonaws.com"
      }
    }
  ]
}
EOF

  tags = {
    Name        = "${var.project}-${var.environment}-rds-monitor"
    Environment = var.environment
    Tenant      = var.tenant
    Service     = var.project
  }
}

resource "aws_iam_role_policy_attachment" "monitor-policy-attach" {
  role       = aws_iam_role.rds-monitor.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

locals {
  db_params = yamldecode(file("parameters/${var.project}-${var.environment}.yaml"))
}

resource "aws_db_parameter_group" "default" {
  name   = "${var.project}-${var.environment}-postgres96"
  family = "postgres9.6"

  dynamic "parameter" {
    for_each = local.db_params
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = lookup(parameter.value, "apply_method", null)
    }
  }

}

resource "aws_db_instance" "api-db" {
  identifier                   = "${var.project}-${var.environment}-db"
  parameter_group_name         = aws_db_parameter_group.default.name
  deletion_protection          = true
  engine                       = "postgres"
  engine_version               = "9.6"
  instance_class               = var.db_size
  allocated_storage            = 10
  max_allocated_storage        = 20
  multi_az                     = false
  backup_retention_period      = 7
  backup_window                = "00:00-00:30"
  copy_tags_to_snapshot        = true
  auto_minor_version_upgrade   = true
  maintenance_window           = "tue:02:00-tue:03:00"
  monitoring_interval          = var.monitor_interval
  monitoring_role_arn          = var.monitor_interval > 0 ? aws_iam_role.rds-monitor.arn : null
  #performance_insights_enabled = var.performance_insight
  skip_final_snapshot          = false
  final_snapshot_identifier    = "${var.project}-${var.environment}-db-final-snapshot"
  storage_encrypted            = true
  db_subnet_group_name         = aws_db_subnet_group.monarch.name
  vpc_security_group_ids       = [aws_security_group.db.id]
  username                     = var.db_username
  password                     = var.db_password
  tags = {
    Name        = "${var.project}-${var.environment}-db"
    Environment = var.environment
    Tenant      = var.tenant
  }
  depends_on = [
    aws_db_parameter_group.default,
    aws_iam_role.rds-monitor
  ]
}

resource "aws_service_discovery_private_dns_namespace" "kong" {
  name        = "${var.environment}.${var.aws_region}"
  description = "KONG ${var.environment} service namespace"
  vpc         = data.aws_vpc.monarch.id
}

resource "aws_service_discovery_service" "kong" {
  name = "kong"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.kong.id
    dns_records {
      ttl  = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }
}
