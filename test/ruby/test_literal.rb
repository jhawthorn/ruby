# -*- coding: us-ascii -*-
# frozen_string_literal: false
require 'test/unit'

class TestRubyLiteral < Test::Unit::TestCase
  def test_float
    chars = ['0', '1', '_', '9', 'f', '.']
    6.times {|len|
      a = ['']
      len.times { a = a.product(chars).map {|x| x.join('') } }
      a.each {|s|
        next if s.empty? || /\.\z/ =~ s || /\A[-+]?\./ =~ s || /\A[-+]?0/ =~ s
        begin
          r1 = Float(s)
        rescue ArgumentError
          r1 = :err
        end
        begin
          r2 = eval(s)
        rescue NameError, SyntaxError
          r2 = :err
        end
        r2 = :err if Range === r2
        assert_equal(r1, r2, "Float(#{s.inspect}) != eval(#{s.inspect})")
      }
    }
  end
end
