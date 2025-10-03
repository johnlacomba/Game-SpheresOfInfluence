resource "aws_ecs_cluster" "main" {
  count = local.enable_ecs ? 1 : 0

  name = "${local.project_name}-${local.environment}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "backend" {
  count = local.enable_ecs ? 1 : 0

  name              = "/ecs/${local.project_name}-backend"
  retention_in_days = 30

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "frontend" {
  count = local.enable_ecs ? 1 : 0

  name              = "/ecs/${local.project_name}-frontend"
  retention_in_days = 30

  tags = local.common_tags
}

resource "aws_iam_role" "ecs_execution" {
  count = local.enable_ecs ? 1 : 0

  name = "${local.project_name}-${local.environment}-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  count      = local.enable_ecs ? 1 : 0
  role       = aws_iam_role.ecs_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  count = local.enable_ecs ? 1 : 0

  name = "${local.project_name}-${local.environment}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "backend" {
  count = local.enable_ecs ? 1 : 0

  family                   = "${local.project_name}-backend"
  cpu                      = "512"
  memory                   = "1024"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[0].arn

  container_definitions = jsonencode([
    {
      name      = "backend"
      image     = var.backend_image
      essential = true
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "PORT", value = "8080" },
        { name = "GAME_WIDTH", value = tostring(var.game_width) },
        { name = "GAME_HEIGHT", value = tostring(var.game_height) },
        { name = "GAME_RESOURCE_TILES", value = tostring(var.game_resource_tiles) },
        { name = "GAME_TICK_MS", value = tostring(var.game_tick_ms) },
        { name = "COGNITO_REGION", value = var.aws_region },
        { name = "COGNITO_USER_POOL_ID", value = aws_cognito_user_pool.main.id },
        { name = "COGNITO_APP_CLIENT_ID", value = aws_cognito_user_pool_client.main.id },
        { name = "CORS_ALLOWED_ORIGIN", value = "*" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend[0].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "frontend" {
  count = local.enable_ecs ? 1 : 0

  family                   = "${local.project_name}-frontend"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[0].arn

  container_definitions = jsonencode([
    {
      name      = "frontend"
      image     = var.frontend_image
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.frontend[0].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "backend" {
  count = local.enable_ecs ? 1 : 0

  name            = "${local.project_name}-backend"
  cluster         = aws_ecs_cluster.main[0].id
  task_definition = aws_ecs_task_definition.backend[0].arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = module.vpc.public_subnets
    security_groups = [aws_security_group.tasks[0].id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend[0].arn
    container_name   = "backend"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.backend]
}

resource "aws_ecs_service" "frontend" {
  count = local.enable_ecs ? 1 : 0

  name            = "${local.project_name}-frontend"
  cluster         = aws_ecs_cluster.main[0].id
  task_definition = aws_ecs_task_definition.frontend[0].arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = module.vpc.public_subnets
    security_groups = [aws_security_group.tasks[0].id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend[0].arn
    container_name   = "frontend"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.frontend]
}
