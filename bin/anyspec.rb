#!/usr/bin/env ruby
# frozen_string_literal: true

# Entry point for Spinel-compiled binary and CRuby execution

require_relative '../lib/anyspec'

exit Anyspec::CLI.new(ARGV).run
