require 'objspace'
class A
  def initialize
    # root shape
    @a = 1 # 0 -> no cache
    @b = 2 # no cache -> no cache
    @c = 3 # overwriting table
    @d = 4 #
  end

  def f=(num)
    @f = num
  end
  def e
    @e
  end
end

a = A.new
ObjectSpace.shape_id(a)
ObjectSpace.shape_transition_tree
exit
shape = ObjectSpace.debug_shape(a)
while !shape.root?
  puts shape.edge_name
  shape = shape.parent
end
exit

class B ; end

class C
  def initialize
    @a = 1
  end
end

count = ObjectSpace.shape_count
loop do
  b = B.new
  b.instance_variable_set(:"@a#{count}", count)
  break if count == ObjectSpace.shape_count
  count = ObjectSpace.shape_count
end

p "done"

a = A.new
a.instance_variable_set(:@e, 8)
p a.instance_variable_get(:@e)
p a.e
p a.instance_variable_get(:@b)
a.f = 8

p a.instance_variables

b = B.new
p b.instance_variables
b.instance_variable_set(:@b, 123)
p b.instance_variables

c = C.new
p c.instance_variables
c.instance_variable_set(:@c, 123)
p c.instance_variable_get(:@a)
p c.instance_variable_get(:@c)
p c.instance_variables


__END__
exit
# 66_000.times { Object.new.instance_variable_set(:"@a#{rand.to_s.delete('.e-')}", 1) }
o = Object.new
o.instance_variable_set(:@a, 1)
p o.instance_variable_get(:@a)
