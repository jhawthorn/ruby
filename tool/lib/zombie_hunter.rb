# frozen_string_literal: true

# Reaps child processes left behind by each test and fails the test if any
# were.  Set RUBY_TEST_NO_ZOMBIE_HUNTER to turn it off, when something other
# than the tests starts child processes of Ruby (as clang's ThreadSanitizer
# runtime does with llvm-symbolizer, which never exits).
module ZombieHunter
  def after_teardown
    super
    assert_empty(Process.waitall)
  end
end

Test::Unit::TestCase.include ZombieHunter unless ENV["RUBY_TEST_NO_ZOMBIE_HUNTER"]
