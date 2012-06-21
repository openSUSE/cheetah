require "abstract_method"
require "logger"
require "shellwords"
require "stringio"

require File.expand_path(File.dirname(__FILE__) + "/cheetah/version")

# Your swiss army knife for executing external commands in Ruby safely and
# conveniently.
#
# ## Features
#
#   * Easy passing of command input
#   * Easy capturing of command output (standard, error, or both)
#   * Piping commands together
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
# @example Run a command and capture its output into a stream
#   File.open("files.txt", "w") do |stdout|
#     Cheetah.run("ls", "-la", :stdout => stdout)
#   end
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
  # Exception raised when a command execution fails.
  class ExecutionFailed < StandardError
    # @return [Array<Array<String>>] the executed commands as an array where
    #   each item is again an array containing an executed command in the first
    #   element and its arguments in the remaining ones
    attr_reader :commands

    # @return [Process::Status] the executed command exit status
    attr_reader :status

    # @return [String, nil] the output the executed command wrote to stdout; can
    #   be `nil` if stdout was captured into a stream
    attr_reader :stdout

    # @return [String, nil] the output the executed command wrote to stderr; can
    #   be `nil` if stderr was captured into a stream
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

  # Defines a recorder interface. Recorder is an object that handles recording
  # of the command execution into a logger. It decides what exactly gets logged,
  # at what level and using what messages.
  #
  # @abstract
  class Recorder
    # @!method record_commands(commands)
    #   Called to record the executed commands.
    #
    #   @abstract
    #   @param [Array<Array<String>>] commands the executed commands as an array
    #     where each item is again an array containing an executed command in
    #     the first element and its arguments in the remaining ones
    abstract_method :record_commands

    # @!method record_stdin(stdin)
    #   Called to record the executed command input (if it wasn't read from a
    #   stream).
    #
    #   @abstract
    #   @param [String] stdin the executed command input
    abstract_method :record_stdin

    # @!method record_status(status)
    #   Called to record the executed command exit status.
    #
    #   @abstract
    #   @param [Process::Status] status the executed command exit status
    abstract_method :record_status

    # @!method record_stdout(stdout)
    #   Called to record the output the executed command wrote to stdout (if it
    #   wasn't captured into a stream).
    #
    #   @abstract
    #   @param [String] stdout the output the executed command wrote to stdout
    abstract_method :record_stdout

    # @!method record_stderr(stderr)
    #   Called to record the output the executed command wrote to stderr (if it
    #   wasn't captured into a stream).
    #
    #   @abstract
    #   @param [String] stderr the output the executed command wrote to stderr
    abstract_method :record_stderr
  end

  # A recorder that does not record anyting. Used by {Cheetah.run} when no
  # logger is passed.
  class NullRecorder < Recorder
    def record_commands(commands); end
    def record_stdin(stdin);       end
    def record_status(status);     end
    def record_stdout(stdout);     end
    def record_stderr(stderr);     end
  end

  # A default recorder. It uses the `Logger::INFO` level for normal messages and
  # the `Logger::ERROR` level for messages about errors (non-zero exit status or
  # non-empty error output). Used by {Cheetah.run} when a logger is passed.
  class DefaultRecorder < Recorder
    def initialize(logger)
      @logger = logger
    end

    def record_commands(commands)
      @logger.info "Executing #{format_commands(commands)}."
    end

    def record_stdin(stdin)
      @logger.info "Standard input: #{format_input_output(stdin)}"
    end

    def record_status(status)
      @logger.send status.success? ? :info : :error,
        "Status: #{status.exitstatus}"
    end

    def record_stdout(stdout)
      @logger.info "Standard output: #{format_input_output(stdout)}"
    end

    def record_stderr(stderr)
      @logger.send stderr.empty? ? :info : :error,
        "Error output: #{format_input_output(stderr)}"
    end

    protected

    def format_input_output(s)
      s.empty? ? "(none)" : s
    end

    def format_commands(commands)
      '"' + commands.map { |c| Shellwords.join(c) }.join(" | ") + '"'
    end
  end

  # @private
  BUILTIN_DEFAULT_OPTIONS = {
    :stdin              => "",
    :stdout             => nil,
    :stderr             => nil,
    :logger             => nil
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

    # Runs external command(s) with specified arguments.
    #
    # If the execution succeeds, the returned value depends on the value of the
    # `:stdout` and `:stderr` options (see below). If the execution fails, the
    # method raises an {ExecutionFailed} exception with detailed information
    # about the failure. (In the single command case, the execution succeeds if
    # the command can be executed and returns a zero exit status. In the
    # multiple command case, the execution succeeds if the last command can be
    # executed and returns a zero exit status.)
    #
    # Commands and their arguments never undergo shell expansion — they are
    # passed directly to the operating system. While this may create some
    # inconvenience in certain cases, it eliminates a whole class of security
    # bugs.
    #
    # The execution can be logged using a logger passed in the `:logger` option.
    # If a logger is set, the method will log the executed command(s), final
    # exit status, passed input and both captured outputs (unless the `:stdin`,
    # `:stdout` or `:stderr` option is set to an `IO`, which prevents logging
    # the corresponding input or output).
    #
    # The actual logging is handled by a separate object called recorder. By
    # default, {DefaultRecorder} instance is used. It uses the `Logger::INFO`
    # level for normal messages and the `Logger::ERROR` level for messages about
    # errors (non-zero exit status or non-empty error output). If you need to
    # customize the recording, you can create your own recorder (implementing
    # the {Recorder} interface) and pass it in the `:recorder` option.
    #
    # Values of options not set using the `options` parameter are taken from
    # {Cheetah.default_options}. If a value is not specified there too, the
    # default value described in the `options` parameter documentation is used.
    #
    # @overload run(command, *args, options = {})
    #   Runs a command with its arguments specified separately.
    #
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
    #   @option options [Recorder, nil] :recorder (DefaultRecorder.new) recorder
    #     to handle the command execution logging
    #
    #   @example
    #     Cheetah.run("tar", "xzf", "foo.tar.gz")
    #
    # @overload run(command_and_args, options = {})
    #   Runs a command with its arguments specified together. This variant is
    #   useful mainly when building the command and its arguments
    #   programmatically.
    #
    #   @param [Array<String>] command_and_args the command to execute (first
    #     element of the array) and its arguments (remaining elements)
    #   @param [Hash] options the options to execute the command with, same as
    #     in the first variant
    #
    #   @example
    #     Cheetah.run(["tar", "xzf", "foo.tar.gz"])
    #
    # @overload run(*commands_and_args, options = {})
    #   Runs multiple commands piped togeter. Standard output of each command
    #   execpt the last one is connected to the standard input of the next
    #   command. Error outputs are aggregated together.
    #
    #   @param [Array<Array<String>>] commands_and_args the commands to execute
    #     as an array where each item is again an array containing an executed
    #     command in the first element and its arguments in the remaining ones
    #   @param [Hash] options the options to execute the commands with, same as
    #     in the first variant
    #
    #   @example
    #     processes = Cheetah.run(["ps", "aux"], ["grep", "ruby"], :stdout => :capture)
    #
    # @raise [ExecutionFailed] when the execution fails
    #
    # @example Run a command and capture its output
    #   files = Cheetah.run("ls", "-la", :stdout => capture)
    #
    # @example Run a command and capture its output into a stream
    #   File.open("files.txt", "w") do |stdout|
    #     Cheetah.run("ls", "-la", :stdout => stdout)
    #   end
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
      streams  = build_streams(options, streamed)
      commands = build_commands(args)
      recorder = build_recorder(options)

      recorder.record_commands(commands)
      recorder.record_stdin(streams[:stdin].string) unless streamed[:stdin]

      pid, pipes = fork_commands(commands)
      select_loop(streams, pipes)
      pid, status = Process.wait2(pid)

      begin
        check_errors(commands, status, streams, streamed)
      ensure
        recorder.record_status(status)
        recorder.record_stdout(streams[:stdout].string) unless streamed[:stdout]
        recorder.record_stderr(streams[:stderr].string) unless streamed[:stderr]
      end

      build_result(streams, options)
    end

    private

    # Parts of Cheetah.run

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

    def build_streams(options, streamed)
      {
        :stdin  => streamed[:stdin]  ? options[:stdin]  : StringIO.new(options[:stdin]),
        :stdout => streamed[:stdout] ? options[:stdout] : StringIO.new(""),
        :stderr => streamed[:stderr] ? options[:stderr] : StringIO.new("")
      }
    end

    def build_commands(args)
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
      # The following code ensures that the result consistently (in all three
      # cases) contains an array of arrays specifying commands and their
      # arguments.
      args.all? { |a| a.is_a?(Array) } ? args : [args]
    end

    def build_recorder(options)
      if options[:recorder]
        options[:recorder]
      else
        options[:logger] ? DefaultRecorder.new(options[:logger]) : NullRecorder.new
      end
    end

    def fork_commands_recursive(commands, pipes)
      fork do
        begin
          if commands.size == 1
            pipes[:stdin][WRITE].close
            STDIN.reopen(pipes[:stdin][READ])
            pipes[:stdin][READ].close
          else
            pipe_to_child = IO.pipe

            fork_commands_recursive(commands[0..-2], {
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

    def fork_commands(commands)
      pipes = { :stdin => IO.pipe, :stdout => IO.pipe, :stderr => IO.pipe }

      pid = fork_commands_recursive(commands, pipes)

      [
        pipes[:stdin][READ],
        pipes[:stdout][WRITE],
        pipes[:stderr][WRITE]
      ].each(&:close)

      [pid, pipes]
    end

    def select_loop(streams, pipes)
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
      outputs = {
        pipes[:stdout][READ] => streams[:stdout],
        pipes[:stderr][READ] => streams[:stderr]
      }
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
          stdin_buffer = streams[:stdin].read(4096) if stdin_buffer.empty?
          if !stdin_buffer
            pipe.close
            next
          end

          n = pipe.syswrite(stdin_buffer)
          stdin_buffer = stdin_buffer[n..-1]
        end
      end
    end

    def check_errors(commands, status, streams, streamed)
      return if status.success?

      stderr_part = if streamed[:stderr]
        " (error output streamed away)"
      elsif streams[:stderr].string.empty?
        " (no error output)"
      else
        lines = streams[:stderr].string.split("\n")
        ": " + lines.first + (lines.size > 1 ? " (...)" : "")
      end

      raise ExecutionFailed.new(
        commands,
        status,
        streamed[:stdout] ? nil : streams[:stdout].string,
        streamed[:stderr] ? nil : streams[:stderr].string,
        "Execution of #{format_commands(commands)} " +
          "failed with status #{status.exitstatus}#{stderr_part}."
      )
    end

    def build_result(streams, options)
      case [options[:stdout] == :capture, options[:stderr] == :capture]
        when [false, false]
          nil
        when [true, false]
          streams[:stdout].string
        when [false, true]
          streams[:stderr].string
        when [true, true]
          [streams[:stdout].string, streams[:stderr].string]
      end
    end

    def format_commands(commands)
      '"' + commands.map { |c| Shellwords.join(c) }.join(" | ") + '"'
    end
  end

  self.default_options = {}
end

