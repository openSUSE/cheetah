# Contains methods for executing external commands safely and conveniently.
module Cheetah
  VERSION = File.read(File.dirname(__FILE__) + "/../VERSION").strip

  @@logger = nil

  # Exception raised when a command execution fails.
  class ExecutionFailed < StandardError
    attr_reader :command, :args, :status, :stdout, :stderr

    def initialize(command, args, status, stdout, stderr, message = nil)
      super(message)
      @command = command
      @args    = args
      @status  = status
      @stdout  = stdout
      @stderr  = stderr
    end
  end

  # Returns the global logger or `nil` if none is set (the default). This logger
  # is used by {Cheetah.run} unless overridden by the `:logger` option.
  def self.logger
    @@logger
  end

  # Sets the global logger. This logger is used by {Cheetah.run} unless
  # overridden by the `:logger` option.
  def self.logger=(logger)
    @@logger = logger
  end

  # Runs an external command, optionally capturing its output. Meant as a safe
  # replacement of <code>\`backticks\`</code>, `Kernel#system` and similar
  # methods, which are often used in unsecure way. (They allow shell expansion
  # of commands, which often means their arguments need proper escaping. The
  # problem is that people forget to do it or do it badly, causing serious
  # security issues.)
  #
  # ### Examples:
  #
  #     # Run a command, grab its output and handle failures.
  #     files = nil
  #     begin
  #       files = Cheetah.run("ls", "-la", :capture => :stdout)
  #     rescue Cheetah::ExecutionFailed => e
  #       puts "Command #{e.command} failed with status #{e.status}."
  #     end
  #
  #     # Log the executed command, it's status, input and both outputs into
  #     # user-supplied logger.
  #     Cheetah.run("qemu-kvm", "foo.raw", :logger => my_logger)
  #
  # The first parameter specifies the command to run, the remaining parameters
  # specify its arguments. It is also possible to specify both the command and
  # arguments in the first parameter using an array. If the last parameter is a
  # hash, it specifies options.
  #
  # For security reasons, the command never goes through shell expansion even if
  # only one parameter is specified (i.e. the method does do not adhere to the
  # convention used by other Ruby methods for launching external commands, e.g.
  # `Kernel#system`).
  #
  # If the command execution succeeds, the returned value depends on the value
  # of the `:capture` option (see below). If it fails (the command is not
  # executed for some reason or returns a non-zero exit status), the method
  # raises a {ExecutionFailed} exception with detailed information about the
  # failure.
  #
  # ### Options:
  #
  #   * `:capture` - configures which output(s) the method captures and returns,
  #                  the valid values are:
  #     * `nil`                - no output is captured and returned
  #                              (the default)
  #     * `:stdout`            - standard output is captured and
  #                              returned as a string
  #     * `:stderr`            - error output is captured and returned
  #                              as a string
  #     * `[:stdout, :stderr]` - both outputs are captured and returned
  #                              as a two-element array of strings
  #
  #   * `:stdin`  - if specified, it is a string sent to command's standard
  #                 input
  #
  #   * `:logger` - if specified, the method will log the command, its status,
  #                 input and both outputs to passed logger at the "debug" level
  def self.run(command, *args)
    options = args.last.is_a?(Hash) ? args.pop : {}

    stdin   = options[:stdin] || ""
    logger  = options[:logger] || @@logger

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

    [pipe_stdin_read, pipe_stdout_write, pipe_stderr_write].each { |p| p.close if p }

    # We write the command's input and read its output using a select loop. Why?
    # Because otherwise we could end up with a deadlock.
    #
    # Imagine if we first read the whole standard output and then the whole
    # error output, but the executed command would write lot of data but only to
    # the error output. Sooner or later it would fill the buffer and block,
    # while we would be blocked on reading the standard output -- classic
    # deadlock.
    #
    # Similar issues can happen with standard input vs. one of the outputs.
    stdout = ""
    stderr = ""
    loop do
      pipes_readable = [pipe_stdout_read, pipe_stderr_read].compact.select { |p| !p.closed? }
      pipes_writable = [pipe_stdin_write].compact.select { |p| !p.closed? }

      break if pipes_readable.empty? && pipes_writable.empty?

      ios_read, ios_write, ios_error = select(pipes_readable, pipes_writable,
        pipes_readable + pipes_writable)

      if !ios_error.empty?
        raise IOError, "Error when communicating with executed program."
      end

      if ios_read.include?(pipe_stdout_read)
        begin
          stdout += pipe_stdout_read.readpartial(4096)
        rescue EOFError
          pipe_stdout_read.close
        end
      end

      if ios_read.include?(pipe_stderr_read)
        begin
          stderr += pipe_stderr_read.readpartial(4096)
        rescue EOFError
          pipe_stderr_read.close
        end
      end

      if ios_write.include?(pipe_stdin_write)
        n = pipe_stdin_write.syswrite(stdin)
        stdin = stdin[n..-1]
        pipe_stdin_write.close if stdin.empty?
      end
    end

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

  def self.describe_args(args)
    args.empty? ? "no arguments" : "arguments #{args.map(&:inspect).join(", ")}"
  end
end
