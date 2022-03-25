# frozen_string_literal: true

class A
  def initialize
    # shape 0
    @a = 1 # shape 0 -> 1
    @b = 1 # shape 1 -> 2
  end

  def set_ivar
    @c = 2 # shape 2 -> 3
  end
end

a = A.new
a.set_ivar

a = A.new # hit!
a.set_ivar #hit!

a = A.new # hit! shape id 2
a.freeze  # 2 -> 4
a.set_ivar # hit!
