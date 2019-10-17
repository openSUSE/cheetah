# frozen_string_literal: true

require File.expand_path(File.dirname(__FILE__) + "/lib/cheetah/version")

Gem::Specification.new do |s|
  s.name        = "cheetah"
  s.version     = Cheetah::VERSION
  s.summary     = "Your swiss army knife for executing external commands in Ruby safely and conveniently."
  s.description = "Your swiss army knife for executing external commands in Ruby safely and conveniently."

  s.author      = "David Majda"
  s.email       = "dmajda@suse.de"
  s.homepage    = "https://github.com/openSUSE/cheetah"
  s.license     = "MIT"

  s.files       = [
    "CHANGELOG",
    "LICENSE",
    "README.md",
    "VERSION",
    "lib/cheetah.rb",
    "lib/cheetah/version.rb"
  ]

  s.add_dependency "abstract_method", "~> 1.2"

  s.add_development_dependency "rspec", "~> 3.3"
  s.add_development_dependency "yard", ">= 0.9.11"
end
