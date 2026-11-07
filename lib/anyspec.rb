# frozen_string_literal: true

require_relative 'anyspec/version'
require_relative 'anyspec/config'
require_relative 'anyspec/spec_loader'
require_relative 'anyspec/runner'
require_relative 'anyspec/result'
require_relative 'anyspec/reporters/json_reporter'
require_relative 'anyspec/reporters/markdown_reporter'
require_relative 'anyspec/reporters/github_actions_reporter'
require_relative 'anyspec/adapter_registry'
require_relative 'anyspec/validator'
require_relative 'anyspec/adapters/base'
require_relative 'anyspec/adapters/generic_cli'
require_relative 'anyspec/adapters/cloud_guard_configuration'
require_relative 'anyspec/adapters/cloud_guard_target'
require_relative 'anyspec/adapters/identity_authentication_policy'
require_relative 'anyspec/adapters/audit_configuration'
require_relative 'anyspec/adapters/object_storage_bucket'
require_relative 'anyspec/external_adapter_loader'
require_relative 'anyspec/cli'

module Anyspec
  class Error < StandardError; end
  class UnknownAdapterError < Error; end
  class SpecValidationError < Error; end
end
