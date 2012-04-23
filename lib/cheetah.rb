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
    # of the `:capture` option (see below). If the command can't be executed for
    # some reason or returns a non-zero exit status, the method raises an
    # {ExecutionFailed} exception with detailed information about the failure.
    #
    # The command and its arguments never undergo shell expansion — they are
    # passed directly to the operating system. While this may create some
    # inconvenience in certain cases, it eliminates a whole class of security
    # bugs.
    #
    # The command execution can be logged using a logger passed in the `:logger`
    # option. If a logger is set, the method will log the command, its status,
    # input and both outputs to it. By default, the `Logger::INFO` level will be
    # used for normal messages and the `Logger::ERROR` level for messages about
    # errors (non-zero exit status or non-empty error output), but this can be
    # changed using the `:logger_level_info` and `:logger_level_error` options.
    #
    # Values of options not set using the `options` parameter are taken from
    # {Cheetah.default_options}. If a value is not specified there too, the
    # default value described in the `options` parameter documentation is used.
    #
    # @overload run(command, *args, options = {})
    #   @param [String] command the command to execute
    #   @param [Array<String>] args the command arguments
    #   @param [Hash] options the options to execute the command with
    #   @option options [String] :stdin ('') command's input
    #   @option options [String,IO] :redirect_stdout (nil) redirect stdout to 
    #     target. If parameter is IO, then write to it. If it is string, then 
    #     open it as file and write there. Redirected stdout means, that stdout
    #     is not logged or captured.
    #   @option options [String] :capture (nil) configures which output(s) to
    #     capture, the valid values are:
    #
    #       * `nil` — no output is captured and returned
    #       * `:stdout` — standard output is captured and returned as a string
    #       * `:stderr` — error output is captured and returned as a string
    #       * `[:stdout, :stderr]` — both outputs are captured and returned as a
    #         two-element array of strings
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
    #   files = Cheetah.run("ls", "-la", :capture => :stdout)
    #
    # @example Run a command and redirect its output to file
    #   Cheetah.run("xzdec", "test.txt.xz", :redirect_stdout => "test.txt")
    #
    # @example Run a command and redirect its output to stream
    #   begin
    #     File.open("test.txt","w") do |f|
    #       Cheetah.run("xzdec", "test.txt.xz", :redirect_stdout => "test.txt")
    #     end
    #   rescue Cheetah::ExecutionFailed
    #     #ensure that we clean output if command failed
    #     FileUtils.rm "test.txt" if File.exists? "test.txt"
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
    def run(command, *args)
      options = args.last.is_a?(Hash) ? args.pop : {}
      options = @default_options.merge(options)
      #handle redirect to file
      if options[:redirect_stdout].is_a? String
        return File.open(options[:redirect_stdout],"w") do |f|
          options[:redirect_stdout] = f
          args << options #merge it back
          run(command,*args)
        end
      end

      stdin              = options[:stdin] || ""
      logger             = options[:logger]
      logger_level_info  = options[:logger_level_info]  || Logger::INFO
      logger_level_error = options[:logger_level_error] || Logger::ERROR

      if command.is_a?(Array)
        args    = command[1..-1]
        command = command.first
      end

      pipe_stdin_read,  pipe_stdin_write  = IO.pipe
      pipe_stdout_read, pipe_stdout_write = IO.pipe
      pipe_stderr_read, pipe_stderr_write = IO.pipe

      if logger
        logger.add logger_level_info,
          "Executing command #{command.inspect} with #{describe_args(args)}."
        logger.add logger_level_info,
          "Standard input: " + (stdin.empty? ? "(none)" : stdin)
      end

      pid = fork do
        begin
          pipe_stdin_write.close
          pipe_stdout_read.close
          pipe_stderr_read.close
          STDERR.reopen(pipe_stderr_write)
          pipe_stderr_write.close
          CommandForker.run(pipe_stdin_read, pipe_stdout_write,[command,args].flatten)
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
      outputs = { 
        pipe_stdout_read => options[:redirect_stdout] || "",
        pipe_stderr_read => ""
      }
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
          logger.add status.success? ? logger_level_info : logger_level_error,
            "Status: #{status.exitstatus}"
          logger.add logger_level_info,
            "Standard output: " + (stdout.empty? ? "(none)" : stdout)
          logger.add stderr.empty?  ? logger_level_info : logger_level_error,
            "Error output: " + (stderr.empty? ? "(none)" : stderr)
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

    def run_piped(*args)
      options = args.last.is_a?(Hash) ? args.pop : {}
      options = @default_options.merge(options)
      #handle redirect to file
      if options[:redirect_stdout].is_a? String
        return File.open(options[:redirect_stdout],"w") do |f|
          options[:redirect_stdout] = f
          args << options #merge it back
          run_piped(*args)
        end
      end

      stdin              = options[:stdin] || ""
      logger             = options[:logger]
      logger_level_info  = options[:logger_level_info]  || Logger::INFO
      logger_level_error = options[:logger_level_error] || Logger::ERROR

      pipe_stdin_read,  pipe_stdin_write  = IO.pipe
      pipe_stdout_read, pipe_stdout_write = IO.pipe
      pipe_stderr_read, pipe_stderr_write = IO.pipe

      if logger
        logger.add logger_level_info,
          "Executing piped command #{args.inspect}." #FIXME refactor command description
        logger.add logger_level_info,
          "Standard input: " + (stdin.empty? ? "(none)" : stdin)
      end

      pid = fork do
        begin
          pipe_stdin_write.close
          pipe_stdout_read.close
          pipe_stderr_read.close
          STDERR.reopen(pipe_stderr_write)
          pipe_stderr_write.close #get stderr only from last command, we don't have enough pipes :)
          CommandForker.run(pipe_stdin_read, pipe_stdout_write, args)
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
      outputs = { 
        pipe_stdout_read => options[:redirect_stdout] || "",
        pipe_stderr_read => ""
      }
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
          logger.add status.success? ? logger_level_info : logger_level_error,
            "Status: #{status.exitstatus}"
          logger.add logger_level_info,
            "Standard output: " + (stdout.empty? ? "(none)" : stdout)
          logger.add stderr.empty?  ? logger_level_info : logger_level_error,
            "Error output: " + (stderr.empty? ? "(none)" : stderr)
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
    class CommandForker
      class << self
        def run(inpipe,outpipe,*args)
          new_outpipe = outpipe
          my_inpipe = inpipe
          if args.size > 1 # we need pipeing
            my_inpipe, new_outpipe = IO.pipe
          end
          STDIN.reopen(my_inpipe)
          my_inpipe.close
          STDOUT.reopen(outpipe)
          outpipe.close
          
          if args.size > 1
            fork do
              begin
                STDERR.close unless STDERR.closed? #we capture stderr only from last command, fixes welcome if it not add lot of pipes
                my_inpipe.close
                CommandForker.run(inpipe,new_outpipe,args[0..-2])
              rescue SystemCallError => e
                exit!(127)
              end
            end
          end
          new_outpipe.close unless new_outpipe.closed?
          my_args = args.last
          exec([my_args.first, my_args.first], *my_args[1..-1])
        end
      end
    end
    def describe_args(args)
      args.empty? ? "no arguments" : "arguments #{args.map(&:inspect).join(", ")}"
    end
  end

  self.default_options = {}
end

