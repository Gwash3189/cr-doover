# `Doover` provides a fluent, type-safe API for retrying Crystal blocks
# with configurable backoff, jitter, and lifecycle hooks.
#
# ### Basic Usage
#
# ```
# require "doover"
#
# result = Doover
#   .exponential
#   .attempts(3)
#   .delay(100.milliseconds)
#   .jitter
#   .max_delay(2.seconds)
#   .work { |attempt| fetch_resource(attempt) }
#   .on_retry do |error, attempt|
#     Log.warn { "attempt #{attempt} failed: #{error.message}" }
#     !error.is_a?(FatalError)
#   end
#   .on_exhausted do |error, attempts|
#     Log.error { "gave up after #{attempts} attempts" }
#   end
#   .run
# ```
module Doover
end

require "./doover/version"
require "./doover/strategy"
require "./doover/config"
require "./doover/backoff"
require "./doover/configurable"
require "./doover/runner"
require "./doover/builder"
