class TLDR
  module Reporters
    class Base
      # Will be called before any tests are run
      def before_suite tldr_config, tests
      end

      # Will be called after each test, unless the run has already been aborted
      def after_test test_result
      end

      # Will be called after all tests have run, unless the run was aborted
      #
      # Exactly ONE of `after_suite`, `after_tldr`, or `after_fail_fast` will be called
      def after_suite tldr_config, test_results
      end

      # Called after the suite-wide time limit expires and the run is aborted
      def after_tldr tldr_config, planned_tests, wip_tests, test_results
      end

      # Called after the first test fails when --fail-fast is enabled, aborting the run
      def after_fail_fast tldr_config, planned_tests, wip_tests, test_results, last_result
      end
    end
  end
end
