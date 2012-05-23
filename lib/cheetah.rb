require "logger"
require "shellwords"

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
#   * Handling of interactive commands
#
# @example Run a command and capture its output
#   files = Cheetah.run("ls", "-la", :stdout => :capture)
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

    # @return [String, nil] the output the executed command wrote to stdout; can
    #   be `nil` if the output was captured into a stream
    attr_reader :stdout

    # @return [String, nil] the output the executed command wrote to stderr; can
    #   be `nil` if the output was captured into a stream
    attr_reader :stderr

    # Initializes a new {ExecutionFailed} instance.
    #
    # @param [String] command the executed command
    # @param [Array<String>] args the executed command arguments
    # @param [Process::Status] status the executed command exit status
    # @param [String, nil] stdout the output the executed command wrote to stdout
    # @param [String, nil] stderr the output the executed command wrote to stderr
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

  # @private
  class LogAdapter
    def initialize(logger, level_info, level_error)
      @logger, @level_info, @level_error = logger, level_info, level_error
    end

    def info(message)
      @logger.add(@level_info, message) if @logger
    end

    def error(message)
      @logger.add(@level_error, message) if @logger
    end
  end

  # @private
  BUILTIN_DEFAULT_OPTIONS = {
    :stdin              => "",
    :stdout             => nil,
    :stderr             => nil,
    :logger             => nil,
    :logger_level_info  => Logger::INFO,
    :logger_level_error => Logger::ERROR
  }

  # @private
  READ  = 0
  WRITE = 1

  class << self
    # The default options of the {Cheetah.run} method. Values of options not
    # specified in its `options` parameter are taken from here. If a value is
    # not specified here too, the default value described in the {Cheetah.run}
    # documentation is used.
    #
    # By default, no values are specified here.
    #
    # @example Setting a logger once for execution of multiple commands
    #   Cheetah.default_options = { :logger = my_logger }
    #   Cheetah.run("./configure")
    #   Cheetah.run("make")
    #   Cheetah.run("make", "install")
    #   Cheetah.default_options = {}
    #
    # @return [Hash] the default options of the {Cheetah.run} method
    attr_accessor :default_options

    # Runs an external command with specified arguments, optionally passing it
    # an input and capturing its output.
    #
    # If the command execution succeeds, the returned value depends on the value
    # of the `:stdout` and `:stderr` options (see below). If the command can't
    # be executed for some reason or returns a non-zero exit status, the method
    # raises an {ExecutionFailed} exception with detailed information about the
    # failure.
    #
    # The command and its arguments never undergo shell expansion — they are
    # passed directly to the operating system. While this may create some
    # inconvenience in certain cases, it eliminates a whole class of security
    # bugs.
    #
    # The command execution can be logged using a logger passed in the `:logger`
    # option. If a logger is set, the method will log the command, its status,
    # input and both outputs to it (the outputs are not logged if they are
    # streamed into an `IO` — see the `:stdout` and `:stderr` options).
    #
    # By default, the `Logger::INFO` level will be used for normal messages and
    # the `Logger::ERROR` level for messages about errors (non-zero exit status
    # or non-empty error output), but this can be changed using the
    # `:logger_level_info` and `:logger_level_error` options.
    #
    # Values of options not set using the `options` parameter are taken from
    # {Cheetah.default_options}. If a value is not specified there too, the
    # default value described in the `options` parameter documentation is used.
    #
    # @overload run(command, *args, options = {})
    #   @param [String] command the command to execute
    #   @param [Array<String>] args the command arguments
    #   @param [Hash] options the options to execute the command with
    #   @option options [String, IO] :stdin ('') a `String` to use as command's
    #     standard input or an `IO` to read it from
    #   @option options [nil, :capture, IO] :stdout (nil) specifies command's
    #     standard output handling
    #
    #     * if set to `nil`, ignore the output
    #     * if set to `:capture`, capture the output and return it as a string
    #       (or as the first element of a two-element array of strings if the
    #       `:stderr` option is set to `:capture` too)
    #     * if set to an `IO`, write the ouptut into it gradually as the command
    #       produces it
    #   @option options [nil, :capture, IO] :stderr (nil) specifies command's
    #     error output handling
    #
    #     * if set to `nil`, ignore the output
    #     * if set to `:capture`, capture the output and return it as a string
    #       (or as the second element of a two-element array of strings if the
    #       `:stdout` option is set to `:capture` too)
    #     * if set to an `IO`, write the ouptut into it gradually as the command
    #       produces it
    #   @option options [Logger, nil] :logger (nil) logger to log the command
    #     execution
    #   @option options [Integer] :logger_level_info (Logger::INFO) level for
    #     logging normal messages; makes sense only if `:logger` is specified
    #   @option options [Integer] :logger_level_error (Logger::ERROR) level for
    #     logging error messages; makes sense only if `:logger` is specified
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
    #   files = Cheetah.run("ls", "-la", :stdout => capture)
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
      options = BUILTIN_DEFAULT_OPTIONS.merge(@default_options).merge(options)

      stdin = if options[:stdin].is_a?(String)
        StringIO.new(options[:stdin])
      else
        options[:stdin]
      end

      # The assumption here is that anything except :capture and nil is an
      # IO-like object. We avoid detecting it directly to allow passing
      # StringIO, mocks, etc.
      streaming_stdout = ![nil, :capture].include?(options[:stdout])
      streaming_stderr = ![nil, :capture].include?(options[:stderr])
      stdout = streaming_stdout ? options[:stdout] : StringIO.new("")
      stderr = streaming_stderr ? options[:stderr] : StringIO.new("")

      logger = LogAdapter.new(options[:logger],
        options[:logger_level_info],
        options[:logger_level_error])

      if command.is_a?(Array)
        args    = command[1..-1]
        command = command.first
      end

      logger.info "Executing command #{format_command(command, args)}."
      if options[:stdin].is_a?(String)
        logger.info "Standard input: " +
          (options[:stdin].empty? ? "(none)" : options[:stdin])
      end

      pipes = { :stdin => IO.pipe, :stdout => IO.pipe, :stderr => IO.pipe }

      pid = fork do
        begin
          pipes[:stdin][WRITE].close
          STDIN.reopen(pipes[:stdin][READ])
          pipes[:stdin][READ].close

          pipes[:stdout][READ].close
          STDOUT.reopen(pipes[:stdout][WRITE])
          pipes[:stdout][WRITE].close

          pipes[:stderr][READ].close
          STDERR.reopen(pipes[:stderr][WRITE])
          pipes[:stderr][WRITE].close

          # All file descriptors from 3 above should be closed here, but since I
          # don't know about any way how to detect the maximum file descriptor
          # number portably in Ruby, I didn't implement it. Patches welcome.

          exec([command, command], *args)
        rescue SystemCallError => e
          exit!(127)
        end
      end

      [
        pipes[:stdin][READ],
        pipes[:stdout][WRITE],
        pipes[:stderr][WRITE]
      ].each { |p| p.close }

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
      stdin_buffer = ""
      outputs = { pipes[:stdout][READ] => stdout, pipes[:stderr][READ] => stderr }
      pipes_readable = [pipes[:stdout][READ], pipes[:stderr][READ]]
      pipes_writable = [pipes[:stdin][WRITE]]
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
          stdin_buffer = stdin.read(4096) if stdin_buffer.empty?
          if !stdin_buffer
            pipe.close
            next
          end

          n = pipe.syswrite(stdin_buffer)
          stdin_buffer = stdin_buffer[n..-1]
        end
      end

      pid, status = Process.wait2(pid)
      begin
        if !status.success?
          raise ExecutionFailed.new(
            command,
            args,
            status,
            streaming_stdout ? nil : stdout.string,
            streaming_stderr ? nil : stderr.string,
            "Execution of command #{format_command(command, args)} " +
              "failed with status #{status.exitstatus}."
          )
        end
      ensure
        logger.send status.success? ? :info : :error,
          "Status: #{status.exitstatus}"
        unless streaming_stdout
          logger.info "Standard output: " +
            (stdout.string.empty? ? "(none)" : stdout.string)
        end
        unless streaming_stderr
          logger.send stderr.string.empty? ? :info : :error,
            "Error output: " + (stderr.string.empty? ? "(none)" : stderr.string)
        end
      end

      case [options[:stdout] == :capture, options[:stderr] == :capture]
        when [false, false]
          nil
        when [true, false]
          stdout.string
        when [false, true]
          stderr.string
        when [true, true]
          [stdout.string, stderr.string]
      end
    end

    private

    def format_command(command, args)
      "\"#{Shellwords.join([command] + args)}\""
    end
  end

  self.default_options = {}
end

