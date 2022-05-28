# frozen_string_literal: false
require "test/unit"
require "objspace"
begin
  require "json"
rescue LoadError
end

class TestObjSpace < Test::Unit::TestCase
  def test_count_imemo_objects
    res = ObjectSpace.count_imemo_objects
    assert_not_empty res.inspect
  end
end
