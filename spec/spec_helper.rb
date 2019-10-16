if ENV["COVERAGE"] || ENV["TRAVIS"]
  require "simplecov"
  SimpleCov.start

  # use coveralls for on-line code coverage reporting at Travis CI
  if ENV["TRAVIS"]
    require "coveralls"
    SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new(
      SimpleCov::Formatter::HTMLFormatter,
      Coveralls::SimpleCov::Formatter
    )
  end
end

require File.expand_path(File.dirname(__FILE__) + "/../lib/cheetah")

RSpec.configure do |c|
  c.color = true
end

RSpec::Matchers.define :touch do |*files|
  match do |proc|
    proc.call
    files.all? { |f| File.exist?(f) }
  end

  def supports_block_expectations?
    true
  end
end

RSpec::Matchers.define :write do |output|
  chain :into do |file|
    @file = file
  end

  match do |proc|
    proc.call
    expect(File.read(@file)).to eq output
  end

  def supports_block_expectations?
    true
  end
end
