require "irb"
require "concurrent"

class TLDR
  class Runner
    def initialize
      @wip = Concurrent::Array.new
      @results = Concurrent::Array.new
      @run_aborted = Concurrent::AtomicBoolean.new false
    end

    def run config, plan
      @wip.clear
      @results.clear

      time_bomb = Thread.new {
        explode = proc do
          next if @run_aborted.true?
          @run_aborted.make_true
          config.reporter.after_tldr config, plan.tests, @wip.dup, @results.dup
          exit! 3
        end

        sleep 1.8
        wait_for_irb_to_exit(&explode)
      }

      results = parallelize(plan.tests, config.workers) { |test|
        e = nil
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
        wip_test = WIPTest.new test, start_time
        @wip << wip_test
        runtime = time_it(start_time) do
          instance = test.klass.new
          instance.setup if instance.respond_to? :setup
          instance.send(test.method)
          instance.teardown if instance.respond_to? :teardown
        rescue Skip, Failure, StandardError => e
        end
        TestResult.new(test, e, runtime).tap do |result|
          next if @run_aborted.true?
          @results << result
          @wip.delete wip_test
          config.reporter.after_test result
          fail_fast config, plan, result if result.failing? && config.fail_fast
        end
      }.tap do
        time_bomb.kill
      end

      unless @run_aborted.true?
        config.reporter.after_suite config, results
        exit exit_code results
      end
    end

    private

    def parallelize tests, workers, &blk
      return tests.map(&blk) if tests.size < 2 || workers < 2
      group_size = (tests.size.to_f / workers).ceil
      tests.each_slice(group_size).map { |group|
        Concurrent::Promises.future {
          group.map(&blk)
        }
      }.flat_map(&:value)
    end

    def fail_fast config, plan, fast_failed_result
      unless @run_aborted.true?
        @run_aborted.make_true
        abort = proc do
          config.reporter.after_fail_fast config, plan.tests, @wip.dup, @results.dup, fast_failed_result
          exit! exit_code([fast_failed_result])
        end
        wait_for_irb_to_exit(&abort)
      end
    end

    def time_it(start)
      yield
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond) - start) / 1000.0).round
    end

    def exit_code results
      if results.any? { |result| result.error? }
        2
      elsif results.any? { |result| result.failure? }
        1
      else
        0
      end
    end

    # Don't hard-kill the runner if user is debugging, it'll
    # screw up their terminal slash be a bad time
    def wait_for_irb_to_exit(&blk)
      if IRB.CurrentContext
        IRB.conf[:AT_EXIT] << blk
      else
        blk.call
      end
    end
  end
end
