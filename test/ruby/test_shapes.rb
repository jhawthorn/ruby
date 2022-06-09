# frozen_string_literal: false
require 'test/unit'

class TestShapes < Test::Unit::TestCase
  class Example
    def meth
      @a = 1
      self
    end

    def meth2
      @a = 1
      self
    end

    def meth3
      @b = 2
      self
    end
  end

  class Example2
    def initialize
      @a = 1
    end

    def e2meth
      @c = 1
      self
    end
  end

  def test_initial_shape
    assert_equal(0, RubyVM.debug_shape(Example.new).id)
  end

  def test_initial_shape_with_vars
    assert_not_equal(0, RubyVM.debug_shape(Example2.new).id)
  end

  def test_transition
    assert_not_equal(RubyVM.debug_shape(Example.new).id, RubyVM.debug_shape(Example.new.meth).id)
  end

  def test_transition_same_ivar_twice
    e = Example.new
    assert_equal(RubyVM.debug_shape(e.meth).id, RubyVM.debug_shape(e.meth2).id)
  end

  def test_object_duplication
    o = Object.new
    assert_equal(RubyVM.debug_shape(o).id, RubyVM.debug_shape(o.dup).id)
  end

  def test_special_const
    assert(RubyVM.debug_shape(true))
  end

  def test_freezing_and_duplicating_object
    obj = Object.new.freeze
    obj2 = obj.dup
    refute_predicate(obj2, :frozen?)
    refute_equal(RubyVM.debug_shape(obj).id, RubyVM.debug_shape(obj2).id)
  end

  def test_freezing_and_duplicating_object_with_ivars
    example = Example2.new.freeze
    example2 = example.dup
    refute_predicate(example2, :frozen?)
    refute_equal(RubyVM.debug_shape(example).id, RubyVM.debug_shape(example2).id)
    assert_equal(example2.instance_variable_get(:@a), 1)
  end

  def test_freezing_and_duplicating_string
    str = "str".freeze
    str2 = str.dup
    refute_predicate(str2, :frozen?)
    refute_equal(RubyVM.debug_shape(str).id, RubyVM.debug_shape(str2).id)
  end

  def test_freezing_and_duplicating_string_with_ivars
    str = "str"
    str.instance_variable_set(:@a, 1)
    str.freeze
    str2 = str.dup
    refute_predicate(str2, :frozen?)
    refute_equal(RubyVM.debug_shape(str).id, RubyVM.debug_shape(str2).id)
    assert_equal(str2.instance_variable_get(:@a), 1)
  end

  def test_inheritance
    # TODO around Example2 in here

  end
end
