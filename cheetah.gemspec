# -*- encoding: utf-8 -*-

require File.expand_path(File.dirname(__FILE__) + "/lib/cheetah")

Gem::Specification.new do |s|
  s.name        = "cheetah"
  s.version     = Cheetah::VERSION
  s.summary     = "Simple library for executing external commands safely and conveniently"
  s.description = <<-EOT.split("\n").map(&:strip).join(" ")
    Cheetah is a simple library for executing external commands safely and
    conveniently. It is meant as a safe replacement of `backticks`,
    Kernel#system and similar methods, which are often used in unsecure way
    (they allow shell expansion of commands).
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
    "lib/cheetah.rb"
  ]

  s.add_development_dependency "rspec"
end
