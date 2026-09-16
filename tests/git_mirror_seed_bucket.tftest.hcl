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

run "seed_bucket_is_passed_to_the_bootstrap_and_readable_by_instances" {
  command = plan

  variables {
    buildkite_agent_token_parameter_store_path = "/buildkite/test-token"
    secrets_bucket                             = "test-secrets-bucket"
    buildkite_agent_enable_git_mirrors         = true
    git_mirror_seed_bucket                     = "test-seed-bucket"
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.agent_launch_template.user_data), "BUILDKITE_GIT_MIRROR_SEED_BUCKET=\"test-seed-bucket\"")
    error_message = "Managed user data should pass the seed bucket to the agent bootstrap script."
  }

  assert {
    condition     = strcontains(aws_iam_role_policy.buildkite_agent_policy[0].policy, "arn:aws:s3:::test-seed-bucket/git-mirror-seeds/*")
    error_message = "The instance role should be allowed to read seed archives from the bucket."
  }
}

run "seed_bucket_is_ignored_when_git_mirrors_are_disabled" {
  command = plan

  variables {
    buildkite_agent_token_parameter_store_path = "/buildkite/test-token"
    secrets_bucket                             = "test-secrets-bucket"
    buildkite_agent_enable_git_mirrors         = false
    git_mirror_seed_bucket                     = "test-seed-bucket"
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.agent_launch_template.user_data), "BUILDKITE_GIT_MIRROR_SEED_BUCKET=\"\"")
    error_message = "The seed bucket should not reach the bootstrap script when git mirrors are disabled."
  }

  assert {
    condition     = !strcontains(aws_iam_role_policy.buildkite_agent_policy[0].policy, "git-mirror-seeds")
    error_message = "The instance role should not be granted seed bucket access when git mirrors are disabled."
  }
}

run "seed_bucket_is_ignored_on_windows" {
  command = plan

  variables {
    buildkite_agent_token_parameter_store_path = "/buildkite/test-token"
    secrets_bucket                             = "test-secrets-bucket"
    instance_operating_system                  = "windows"
    buildkite_agent_enable_git_mirrors         = true
    git_mirror_seed_bucket                     = "test-seed-bucket"
  }

  assert {
    condition     = !strcontains(aws_iam_role_policy.buildkite_agent_policy[0].policy, "git-mirror-seeds")
    error_message = "Seeding is Linux only, so Windows instances should not be granted seed bucket access."
  }
}
