mock_provider "aws" {
  mock_data "aws_region" {
    override_during = plan
    defaults = {
      id     = "us-east-1"
      region = "us-east-1"
    }
  }

  mock_data "aws_caller_identity" {
    override_during = plan
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:user/test"
      user_id    = "test"
    }
  }

  mock_data "aws_partition" {
    override_during = plan
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_data "aws_availability_zones" {
    override_during = plan
    defaults = {
      names = ["us-east-1a", "us-east-1b"]
    }
  }
}

mock_provider "archive" {}
mock_provider "random" {
  mock_resource "random_id" {
    override_during = plan
    defaults = {
      hex = "01234567"
    }
  }
}

variables {
  buildkite_agent_token_parameter_store_path = "/buildkite/test-token"
  secrets_bucket                             = "test-secrets-bucket"
  instance_types                             = "m6i.xlarge,m6a.xlarge"
}

run "instance_types_list_keeps_one_override_per_type" {
  command = plan

  assert {
    condition     = [for override in aws_autoscaling_group.agent_auto_scale_group.mixed_instances_policy[0].launch_template[0].override : override.instance_type] == ["m6i.xlarge", "m6a.xlarge"]
    error_message = "Without instance_requirements the group should keep one override per listed instance type, in order."
  }

  assert {
    condition     = aws_autoscaling_group.agent_auto_scale_group.mixed_instances_policy[0].instances_distribution[0].on_demand_allocation_strategy == "prioritized"
    error_message = "Without instance_requirements On-Demand instances should follow the instance_types order."
  }
}

run "instance_requirements_replace_the_instance_types_list" {
  command = plan

  variables {
    instance_requirements = {
      vcpu_count                                  = { min = 4, max = 4 }
      memory_mib                                  = { min = 16384, max = 32768 }
      spot_max_price_percentage_over_lowest_price = 60
    }
  }

  assert {
    condition     = length(aws_autoscaling_group.agent_auto_scale_group.mixed_instances_policy[0].launch_template[0].override) == 1
    error_message = "instance_requirements should replace the per-type overrides with a single override."
  }

  assert {
    condition     = aws_autoscaling_group.agent_auto_scale_group.mixed_instances_policy[0].launch_template[0].override[0].instance_requirements[0].spot_max_price_percentage_over_lowest_price == 60
    error_message = "The spot price protection threshold should reach the Auto Scaling group."
  }

  assert {
    condition     = aws_autoscaling_group.agent_auto_scale_group.mixed_instances_policy[0].instances_distribution[0].on_demand_allocation_strategy == "lowest-price"
    error_message = "AWS rejects 'prioritized' with instance requirements, so On-Demand instances should use 'lowest-price'."
  }
}
