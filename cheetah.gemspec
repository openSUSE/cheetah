# -*- encoding: utf-8 -*-

require File.expand_path(File.dirname(__FILE__) + "/lib/cheetah/version")

Gem::Specification.new do |s|
  s.name        = "cheetah"
  s.version     = Cheetah::VERSION
  s.summary     = "Simple library for executing external commands safely and conveniently"
  s.description = <<-EOT.split("\n").map(&:strip).join(" ")
    Cheetah is a simple library for executing external commands safely and
    conveniently.
  EOT

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

  s.add_development_dependency "rspec"
  s.add_development_dependency "redcarpet"
  s.add_development_dependency "yard"
end
