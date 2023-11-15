terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

resource "aws_vpc" "LLMResearchVPC" {
  cidr_block       = "172.31.0.0/16"
  instance_tenancy = "default"
}

resource "aws_security_group" "LLMResearchSecurityGroup" {
  name        = "LLMResearchSecurityGroup"
  description = "default VPC security group"
  vpc_id      = aws_vpc.LLMResearchVPC.id
  ingress {
    description = "permit all in"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = [aws_vpc.LLMResearchVPC.cidr_block]
  }
  egress {
    description = "permit all out"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}

resource "aws_subnet" "PublicSubnet1" {
  vpc_id                  = aws_vpc.LLMResearchVPC.id
  cidr_block              = "172.31.0.0/20"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "PublicSubnet2" {
  vpc_id                  = aws_vpc.LLMResearchVPC.id
  cidr_block              = "172.31.16.0/20"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "InternetGateway" {
  vpc_id = aws_vpc.LLMResearchVPC.id
}

resource "aws_default_route_table" "example" {
  default_route_table_id = aws_vpc.LLMResearchVPC.default_route_table_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.InternetGateway.id
  }
}

resource "aws_batch_compute_environment" "LLMResearchComputeEnv" {
  compute_environment_name = "LLMResearchComputeEnv"
  compute_resources {
    allocation_strategy = "BEST_FIT_PROGRESSIVE"
    instance_role = join(
      "",
      [
        "arn:aws:iam::",
        data.aws_caller_identity.current.account_id,
        ":instance-profile/ecsInstanceRole"
      ]
    )
    instance_type      = ["p2.xlarge"]
    max_vcpus          = 1
    desired_vcpus      = 1
    min_vcpus          = 0
    security_group_ids = [aws_security_group.LLMResearchSecurityGroup.id]
    subnets = [
      aws_subnet.PublicSubnet1.id,
      aws_subnet.PublicSubnet2.id
    ]
    type = "EC2"
  }
  type  = "MANAGED"
  state = "ENABLED"
}

resource "aws_batch_job_queue" "LLMResearchJobQueue" {
  name     = "LLMResearchJobQueue"
  state    = "ENABLED"
  priority = 0
  compute_environments = [
    join(
      ":",
      [
        "arn:aws:batch",
        var.region,
        data.aws_caller_identity.current.account_id,
        "compute-environment/LLMResearchComputeEnv"
      ]
    )
  ]
  depends_on = [aws_batch_compute_environment.LLMResearchComputeEnv]
}

resource "aws_batch_job_definition" "HelloWorldAllDefaultsJobDefinition" {
  name = "HelloWorldAllDefaultsJobDefinition"
  type = "container"
  container_properties = jsonencode({
    command = ["ls", "-la"],
    image   = "public.ecr.aws/amazonlinux/amazonlinux:latest"
    resourceRequirements = [
      {
        type  = "VCPU"
        value = "1"
      },
      {
        type  = "MEMORY"
        value = "512"
      },
      {
        type  = "GPU"
        value = "1"
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
    }
  })
  platform_capabilities = ["EC2"]
  propagate_tags        = true
  retry_strategy {
    attempts = 1
  }
  timeout {
    attempt_duration_seconds = 3600
  }
}