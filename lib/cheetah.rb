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
    # @return [Array<Array<String>>] the executed commands as an array where
    #   each item is again an array containing an executed command in the first
    #   element and its arguments in the remaining ones
    attr_reader :commands

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
    # @param [Array<Array<String>>] commands the executed commands as an array
    #   where each item is again an array containing an executed command in the
    #   first element and its arguments in the remaining ones
    # @param [Process::Status] status the executed command exit status
    # @param [String, nil] stdout the output the executed command wrote to stdout
    # @param [String, nil] stderr the output the executed command wrote to stderr
    # @param [String, nil] message the exception message
    def initialize(commands, status, stdout, stderr, message = nil)
      super(message)
      @commands = commands
      @status   = status
      @stdout   = stdout
      @stderr   = stderr
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

  READ  = 0 # @private
  WRITE = 1 # @private

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
    def run(*args)
      options = args.last.is_a?(Hash) ? args.pop : {}
      options = BUILTIN_DEFAULT_OPTIONS.merge(@default_options).merge(options)

      streamed = compute_streamed(options)

      stdin  = streamed[:stdin]  ? options[:stdin]  : StringIO.new(options[:stdin])
      stdout = streamed[:stdout] ? options[:stdout] : StringIO.new("")
      stderr = streamed[:stderr] ? options[:stderr] : StringIO.new("")

      logger = LogAdapter.new(options[:logger],
        options[:logger_level_info],
        options[:logger_level_error])

      # There are three valid ways how to call Cheetah.run:
      #
      #   1. Single command, e.g. Cheetah.run("ls", "-la")
      #
      #        args == ["ls", "-la"]
      #
      #   2. Single command passed as an array, e.g. Cheetah.run(["ls", "-la"])
      #
      #        args == [["ls", "-la"]]
      #
      #   3. Piped command, e.g. Cheetah.run(["ps", "aux"], ["grep", "ruby"])
      #
      #        args == [["ps", "aux"], ["grep", "ruby"]]
      #
      # The following code ensures that the "commands" variable consistently (in
      # all three cases) contains an array of arrays specifying commands and
      # their arguments.
      commands = args.all? { |a| a.is_a?(Array) } ? args : [args]

      logger.info "Executing command #{format_commands(commands)}."
      unless streamed[:stdin]
        logger.info "Standard input: " +
          (options[:stdin].empty? ? "(none)" : options[:stdin])
      end

      pipes = { :stdin => IO.pipe, :stdout => IO.pipe, :stderr => IO.pipe }

      pid = fork_commands(commands, pipes)

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
            commands,
            status,
            streamed[:stdout] ? nil : stdout.string,
            streamed[:stderr] ? nil : stderr.string,
            "Execution of command #{format_commands(commands)} " +
              "failed with status #{status.exitstatus}."
          )
        end
      ensure
        logger.send status.success? ? :info : :error,
          "Status: #{status.exitstatus}"
        unless streamed[:stdout]
          logger.info "Standard output: " +
            (stdout.string.empty? ? "(none)" : stdout.string)
        end
        unless streamed[:stderr]
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

    def compute_streamed(options)
      # The assumption for :stdout and :stderr is that anything except :capture
      # and nil is an IO-like object. We avoid detecting it directly to allow
      # passing StringIO, mocks, etc.
      {
        :stdin  => !options[:stdin].is_a?(String),
        :stdout => ![nil, :capture].include?(options[:stdout]),
        :stderr => ![nil, :capture].include?(options[:stderr])
      }
    end

    def fork_commands(commands, pipes)
      fork do
        begin
          if commands.size == 1
            pipes[:stdin][WRITE].close
            STDIN.reopen(pipes[:stdin][READ])
            pipes[:stdin][READ].close
          else
            pipe_to_child = IO.pipe

            fork_commands(commands[0..-2], {
              :stdin  => pipes[:stdin],
              :stdout => pipe_to_child,
              :stderr => pipes[:stderr]
            })

            pipes[:stdin][READ].close
            pipes[:stdin][WRITE].close

            pipe_to_child[WRITE].close
            STDIN.reopen(pipe_to_child[READ])
            pipe_to_child[READ].close
          end

          pipes[:stdout][READ].close
          STDOUT.reopen(pipes[:stdout][WRITE])
          pipes[:stdout][WRITE].close

          pipes[:stderr][READ].close
          STDERR.reopen(pipes[:stderr][WRITE])
          pipes[:stderr][WRITE].close

          # All file descriptors from 3 above should be closed here, but since I
          # don't know about any way how to detect the maximum file descriptor
          # number portably in Ruby, I didn't implement it. Patches welcome.

          command, *args = commands.last
          exec([command, command], *args)
        rescue SystemCallError => e
          exit!(127)
        end
      end
    end

    def format_commands(commands)
      formatted_commands = commands.map do |command, *args|
        Shellwords.join([command] + args)
      end

      "\"#{formatted_commands.join(" | ")}\""
    end
  end

  self.default_options = {}
end

