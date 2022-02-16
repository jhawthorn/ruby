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
    assert_equal(0, ObjectSpace.shape_id(Example.new))
  end

  def test_initial_shape_with_vars
    assert_not_equal(0, ObjectSpace.shape_id(Example2.new))
  end

  def test_transition
    assert_not_equal(ObjectSpace.shape_id(Example.new), ObjectSpace.shape_id(Example.new.meth))
  end

  def test_transition_same_ivar_twice
    e = Example.new
    assert_equal(ObjectSpace.shape_id(e.meth), ObjectSpace.shape_id(e.meth2))
  end

  def test_object_duplication
    o = Object.new
    assert_equal(ObjectSpace.shape_id(o), ObjectSpace.shape_id(o.dup))
  end

  def test_inheritance
    # TODO around Example2 in here

  end
end
