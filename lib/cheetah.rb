# A simple library for executing external commands safely and conveniently.
#
# ## Features
#
#   * Easy passing of command input
#   * Easy capturing of command output (standard, error, or both)
#   * 100% secure (shell expansion is impossible by design)
#   * Raises exceptions on errors (no more manual status code checks)
#   * Optional logging for easy debugging
#
# ## Non-features
#
#   * Handling of commands producing big outputs
#   * Handling of interactive commands
#
# @example Run a command and capture its output
#   files = Cheetah.run("ls", "-la", :capture => :stdout)
#
# @example Run a command and handle errors
#   begin
#     Cheetah.run("rm", "/etc/passwd")
#   rescue Cheetah::ExecutionFailed => e
#     puts e.message
#     puts "Standard output: #{e.stdout}"
#     puts "Error ouptut:    #{e.stderr}"
#   end
module Cheetah
  # Cheetah version (uses [semantic versioning](http://semver.org/)).
  VERSION = File.read(File.dirname(__FILE__) + "/../VERSION").strip

  # Exception raised when a command execution fails.
  class ExecutionFailed < StandardError
    # @return [String] the executed command
    attr_reader :command

    # @return [Array<String>] the executed command arguments
    attr_reader :args

    # @return [Process::Status] the executed command exit status
    attr_reader :status

    # @return [String] the output the executed command wrote to stdout
    attr_reader :stdout

    # @return [String] the output the executed command wrote to stderr
    attr_reader :stderr

    # Initializes a new {ExecutionFailed} instance.
    #
    # @param [String] command the executed command
    # @param [Array<String>] args the executed command arguments
    # @param [Process::Status] status the executed command exit status
    # @param [String] stdout the output the executed command wrote to stdout
    # @param [String] stderr the output the executed command wrote to stderr
    # @param [String, nil] message the exception message
    def initialize(command, args, status, stdout, stderr, message = nil)
      super(message)
      @command = command
      @args    = args
      @status  = status
      @stdout  = stdout
      @stderr  = stderr
    end
  end

  class << self
    # The global logger or `nil` if none is set (the default). This logger is
    # used by {Cheetah.run} unless overridden by the `:logger` option.
    #
    # @return [Logger, nil] the global logger
    attr_accessor :logger

    # Runs an external command with specified arguments, optionally passing it
    # an input and capturing its output.
    #
    # If the command execution succeeds, the returned value depends on the value
    # of the `:capture` option (see below). If the command can't be executed for
    # some reason or returns a non-zero exit status, the method raises an
    # {ExecutionFailed} exception with detailed information about the failure.
    #
    # The command and its arguments never undergo shell expansion — they are
    # passed directly to the operating system. While this may create some
    # inconvenience in certain cases, it eliminates a whole class of security
    # bugs.
    #
    # @overload run(command, *args, options = {})
    #   @param [String] command the command to execute
    #   @param [Array<String>] args the command arguments
    #   @param [Hash] options the options to execute the command with
    #   @option options [String] :stdin ('') command's input
    #   @option options [String] :capture (nil) configures which output(s) to
    #     capture, the valid values are:
    #
    #       * `nil` — no output is captured and returned
    #       * `:stdout` — standard output is captured and returned as a string
    #       * `:stderr` — error output is captured and returned as a string
    #       * `[:stdout, :stderr]` — both outputs are captured and returned as a
    #         two-element array of strings
    #   @option options [Logger] :logger (nil) if specified, the method will log
    #     the command, its status, input and both outputs to the passed logger
    #     at the `debug` level
    #
    # @overload run(command_and_args, options = {})
    #   This variant is useful mainly when building the command and its
    #   arguments programmatically.
    #
    #   @param [Array<String>] command_and_args the command to execute (first
    #     element of the array) and its arguments (remaining elements)
    #   @param [Hash] options the options to execute the command with, same as
    #     in the first variant
    #
    # @raise [ExecutionFailed] when the command can't be executed for some
    #   reason or returns a non-zero exit status
    #
    # @example Run a command and capture its output
    #   files = Cheetah.run("ls", "-la", :capture => :stdout)
    #
    # @example Run a command and handle errors
    #   begin
    #     Cheetah.run("rm", "/etc/passwd")
    #   rescue Cheetah::ExecutionFailed => e
    #     puts e.message
    #     puts "Standard output: #{e.stdout}"
    #     puts "Error ouptut:    #{e.stderr}"
    #   end
    def run(command, *args)
      options = args.last.is_a?(Hash) ? args.pop : {}

      stdin   = options[:stdin] || ""
      logger  = options[:logger] || @logger

      if command.is_a?(Array)
        args    = command[1..-1]
        command = command.first
      end

      pipe_stdin_read,  pipe_stdin_write  = IO.pipe
      pipe_stdout_read, pipe_stdout_write = IO.pipe
      pipe_stderr_read, pipe_stderr_write = IO.pipe

      if logger
        logger.debug "Executing command #{command.inspect} with #{describe_args(args)}."
        logger.debug "Standard input: " + (stdin.empty? ? "(none)" : stdin)
      end

      pid = fork do
        begin
          pipe_stdin_write.close
          STDIN.reopen(pipe_stdin_read)
          pipe_stdin_read.close

          pipe_stdout_read.close
          STDOUT.reopen(pipe_stdout_write)
          pipe_stdout_write.close

          pipe_stderr_read.close
          STDERR.reopen(pipe_stderr_write)
          pipe_stderr_write.close

          # All file descriptors from 3 above should be closed here, but since I
          # don't know about any way how to detect the maximum file descriptor
          # number portably in Ruby, I didn't implement it. Patches welcome.

          exec([command, command], *args)
        rescue SystemCallError => e
          exit!(127)
        end
      end

      [pipe_stdin_read, pipe_stdout_write, pipe_stderr_write].each { |p| p.close }

      # We write the command's input and read its output using a select loop.
      # Why? Because otherwise we could end up with a deadlock.
      #
      # Imagine if we first read the whole standard output and then the whole
      # error output, but the executed command would write lot of data but only
      # to the error output. Sooner or later it would fill the buffer and block,
      # while we would be blocked on reading the standard output -- classic
      # deadlock.
      #
      # Similar issues can happen with standard input vs. one of the outputs.
      outputs = { pipe_stdout_read => "", pipe_stderr_read => "" }
      pipes_readable = [pipe_stdout_read, pipe_stderr_read]
      pipes_writable = [pipe_stdin_write]
      loop do
        pipes_readable.reject!(&:closed?)
        pipes_writable.reject!(&:closed?)

        break if pipes_readable.empty? && pipes_writable.empty?

        ios_read, ios_write, ios_error = select(pipes_readable, pipes_writable,
          pipes_readable + pipes_writable)

        if !ios_error.empty?
          raise IOError, "Error when communicating with executed program."
        end

        ios_read.each do |pipe|
          begin
            outputs[pipe] << pipe.readpartial(4096)
          rescue EOFError
            pipe.close
          end
        end

        ios_write.each do |pipe|
          n = pipe.syswrite(stdin)
          stdin = stdin[n..-1]
          pipe.close if stdin.empty?
        end
      end

      stdout = outputs[pipe_stdout_read]
      stderr = outputs[pipe_stderr_read]

      pid, status = Process.wait2(pid)
      begin
        if !status.success?
          raise ExecutionFailed.new(command, args, status, stdout, stderr,
            "Execution of command #{command.inspect} " +
            "with #{describe_args(args)} " +
            "failed with status #{status.exitstatus}.")
        end
      ensure
        if logger
          logger.debug "Status: #{status.exitstatus}"
          logger.debug "Standard output: " + (stdout.empty? ? "(none)" : stdout)
          logger.debug "Error output: " + (stderr.empty? ? "(none)" : stderr)
        end
      end

      case options[:capture]
        when nil
          nil
        when :stdout
          stdout
        when :stderr
          stderr
        when [:stdout, :stderr]
          [stdout, stderr]
      end
    end

    private

    def describe_args(args)
      args.empty? ? "no arguments" : "arguments #{args.map(&:inspect).join(", ")}"
    end
  end
end
