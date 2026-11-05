# frozen_string_literal: false
require 'test/unit'

# Builtin methods compiled at build time (builtin_aot.c) must behave like
# the interpreter, except that they don't see user redefinitions of builtin
# methods. Run the same script with and without them and compare.
class TestBuiltinAOT < Test::Unit::TestCase
  SCRIPT = <<~'RUBY'
    a = []; 5.times { |i| a << i }; p a
    p 3.times.to_a
    p 0.times { raise }
    p((2**64).times.first(2))
    p 10.times { |i| break i * 100 if i == 4 }
    def ret = 10.times { |i| return i if i == 3 }
    p ret
    begin
      3.times { raise "boom" }
    rescue => e
      p e.message, e.backtrace_locations.map(&:label).first(3)
    end
    p 3.times { next }
    s = 0; 1000.times { |i| s += i }; p s
    x = []; 3.times { |i| 2.times { |j| x << [i, j] } }; p x
    acc = []; 4.times(&acc.method(:<<)); p acc
    p 3.times(&:itself)
    p catch(:t) { 5.times { |i| throw :t, i if i == 2 } }
    f = Fiber.new { 3.times { |i| Fiber.yield i }; :done }
    p 4.times.map { f.resume }
    t = Thread.new { c = 0; 200_000.times { c += 1 }; c }
    c = 0; 200_000.times { c += 1 }; p [t.value, c]
    pr = nil; 2.times { |i| pr = proc { i } }; p pr.call
    lines = 0
    tp = TracePoint.new(:line) { lines += 1 }
    z = []; 5.times { |i| tp.enable if i == 2; z << i }
    tp.disable
    p z, lines > 0
  RUBY

  def test_same_as_interpreter
    expected, = EnvUtil.invoke_ruby([{"RUBY_AOT" => "0"}, "-e", SCRIPT], "", true)
    assert_in_out_err([{"RUBY_AOT" => "1"}, "-e", SCRIPT], "", expected.lines.map(&:chomp), [])
  end

  # Compiled builtins assume methods of builtin classes are the builtin ones
  # (Box keeps user redefinitions away from builtin code); user code still
  # sees its redefinitions.
  REDEFINE = <<~'RUBY'
    $lt = $succ = 0
    Integer.prepend(Module.new { def <(o) = ($lt += 1; super) })
    class Integer
      alias aot_test_succ succ
      def succ = ($succ += 1; aot_test_succ)
    end
    3.times { }
    p [$lt, $succ]
    p 1 < 2, $lt
  RUBY

  def test_builtins_ignore_redefinition
    assert_in_out_err([{"RUBY_AOT" => "1"}, "-e", REDEFINE], "", ["[0, 0]", "true", "1"], [])
  end

  def test_interpreter_sees_redefinition
    assert_in_out_err([{"RUBY_AOT" => "0"}, "-e", REDEFINE], "", ["[4, 3]", "true", "5"], [])
  end
end
